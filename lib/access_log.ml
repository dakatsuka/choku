type request = {
  meth : Method.t;
  target : string;
  headers : Headers.t;
  protocol : string option;
}

type response = { status : Status.t; headers : Headers.t }
type outcome = Returned of response | Raised of exn | Cancelled

type event = {
  request : request;
  outcome : outcome;
  started_at : float option;
  duration_ns : int64 option;
}

type sink = event -> unit
type formatter = event -> string

let status event =
  match event.outcome with
  | Returned response -> Some response.status
  | Raised _ -> Some Status.internal_server_error
  | Cancelled -> None

let request_snapshot request =
  {
    meth = Request.meth request;
    target = Request.target request;
    headers = Request.headers request;
    protocol = Some "HTTP/1.1";
  }

let response_snapshot response =
  { status = Response.status response; headers = Response.headers response }

let duration_ns mono_clock started =
  match (mono_clock, started) with
  | Some mono_clock, Some started ->
      let finished = Eio.Time.Mono.now mono_clock in
      let ns = Mtime.Span.to_uint64_ns (Mtime.span started finished) in
      if ns < 0L then None else Some ns
  | _ -> None

let call_sink sink event =
  match sink event with
  | () -> None
  | exception (Eio.Cancel.Cancelled _ as exn) -> Some exn
  | exception _ -> None

let middleware ?clock ?mono_clock sink next raw_request =
  let request = request_snapshot raw_request in
  let started_at = Option.map Eio.Time.now clock in
  let started_mono = Option.map Eio.Time.Mono.now mono_clock in
  match next raw_request with
  | response ->
      let event =
        {
          request;
          outcome = Returned (response_snapshot response);
          started_at;
          duration_ns = duration_ns mono_clock started_mono;
        }
      in
      (match call_sink sink event with Some exn -> raise exn | None -> ());
      response
  | exception (Eio.Cancel.Cancelled _ as exn) -> raise exn
  | exception exn -> (
      let backtrace = Printexc.get_raw_backtrace () in
      let event =
        {
          request;
          outcome = Raised exn;
          started_at;
          duration_ns = duration_ns mono_clock started_mono;
        }
      in
      match call_sink sink event with
      | Some cancel -> raise cancel
      | None -> Printexc.raise_with_backtrace exn backtrace)

let month_name = function
  | 1 -> "Jan"
  | 2 -> "Feb"
  | 3 -> "Mar"
  | 4 -> "Apr"
  | 5 -> "May"
  | 6 -> "Jun"
  | 7 -> "Jul"
  | 8 -> "Aug"
  | 9 -> "Sep"
  | 10 -> "Oct"
  | 11 -> "Nov"
  | 12 -> "Dec"
  | _ -> invalid_arg "invalid month"

let format_timestamp = function
  | None -> "-"
  | Some timestamp -> (
      match Ptime.of_float_s timestamp with
      | None -> "-"
      | Some timestamp ->
          let (year, month, day), ((hour, minute, second), _) =
            Ptime.to_date_time ~tz_offset_s:0 timestamp
          in
          Printf.sprintf "[%02d/%s/%04d:%02d:%02d:%02d +0000]" day
            (month_name month) year hour minute second)

let hex = "0123456789ABCDEF"

let add_hex_escape buffer code =
  Buffer.add_string buffer "\\x";
  Buffer.add_char buffer hex.[code lsr 4];
  Buffer.add_char buffer hex.[code land 0x0f]

let escape_request_field text =
  let buffer = Buffer.create (String.length text) in
  String.iter
    (fun char ->
      match char with
      | '"' -> Buffer.add_string buffer "\\\""
      | '\\' -> Buffer.add_string buffer "\\\\"
      | '\x00' .. '\x1f' | '\x7f' -> add_hex_escape buffer (Char.code char)
      | _ -> Buffer.add_char buffer char)
    text;
  Buffer.contents buffer

let format_clf_style event =
  let protocol = Option.value event.request.protocol ~default:"HTTP/1.1" in
  let request_line =
    Printf.sprintf "%s %s %s"
      (Method.to_string event.request.meth)
      event.request.target protocol
    |> escape_request_field
  in
  let status =
    event |> status |> Option.map Status.code |> Option.map string_of_int
    |> Option.value ~default:"-"
  in
  Printf.sprintf "- - - %s \"%s\" %s -"
    (format_timestamp event.started_at)
    request_line status

module Writer = struct
  type error =
    | Formatter_failed of exn
    | Write_failed of exn
    | Writer_cancelled of exn

  type overflow = Block | Drop
  type command = Event of event | Flush of (unit, error) result Eio.Promise.u
  type state = Open | Closed of error

  type t = {
    formatter : formatter;
    flow : Eio.Flow.sink_ty Eio.Resource.t;
    overflow : overflow;
    on_error : (error -> unit) option;
    capacity : int;
    queue : command Queue.t;
    mutex : Eio.Mutex.t;
    not_empty : Eio.Condition.t;
    not_full : Eio.Condition.t;
    mutable state : state;
    mutable dropped_count : int;
  }

  let with_lock t fn =
    Eio.Mutex.lock t.mutex;
    match fn () with
    | value ->
        Eio.Mutex.unlock t.mutex;
        value
    | exception exn ->
        Eio.Mutex.unlock t.mutex;
        raise exn

  let resolve_flush resolver result =
    ignore (Eio.Promise.try_resolve resolver result : bool)

  let rec drain_flushes t error =
    if not (Queue.is_empty t.queue) then (
      (match Queue.take t.queue with
      | Flush resolver -> resolve_flush resolver (Error error)
      | Event _ -> ());
      drain_flushes t error)

  let close ?(replace = false) t error =
    with_lock t (fun () ->
        match t.state with
        | Closed _ when not replace -> ()
        | Closed _ | Open ->
            t.state <- Closed error;
            drain_flushes t error;
            Eio.Condition.broadcast t.not_empty;
            Eio.Condition.broadcast t.not_full)

  let report_error t error =
    match t.on_error with
    | None -> ()
    | Some on_error -> (
        match on_error error with
        | () -> ()
        | exception (Eio.Cancel.Cancelled _ as exn) -> raise exn
        | exception _ -> ())

  let enqueue_event_blocking t event =
    with_lock t (fun () ->
        let rec loop () =
          match t.state with
          | Closed _ -> ()
          | Open ->
              if Queue.length t.queue < t.capacity then (
                Queue.add (Event event) t.queue;
                Eio.Condition.broadcast t.not_empty)
              else (
                Eio.Condition.await t.not_full t.mutex;
                loop ())
        in
        loop ())

  let enqueue_event_drop t event =
    with_lock t (fun () ->
        match t.state with
        | Closed _ -> ()
        | Open ->
            if Queue.length t.queue < t.capacity then (
              Queue.add (Event event) t.queue;
              Eio.Condition.broadcast t.not_empty)
            else t.dropped_count <- t.dropped_count + 1)

  let sink t event =
    match t.overflow with
    | Block -> enqueue_event_blocking t event
    | Drop -> enqueue_event_drop t event

  let enqueue_flush t resolver =
    with_lock t (fun () ->
        let rec loop () =
          match t.state with
          | Closed error -> Error error
          | Open ->
              if Queue.length t.queue < t.capacity then (
                Queue.add (Flush resolver) t.queue;
                Eio.Condition.broadcast t.not_empty;
                Ok ())
              else (
                Eio.Condition.await t.not_full t.mutex;
                loop ())
        in
        loop ())

  let flush t =
    let promise, resolver = Eio.Promise.create () in
    match enqueue_flush t resolver with
    | Error error -> Error error
    | Ok () -> Eio.Promise.await promise

  let dropped_count t = with_lock t (fun () -> t.dropped_count)

  let take t =
    with_lock t (fun () ->
        let rec loop () =
          if Queue.is_empty t.queue then (
            match t.state with
            | Closed _ -> None
            | Open ->
                Eio.Condition.await t.not_empty t.mutex;
                loop ())
          else
            let command = Queue.take t.queue in
            Eio.Condition.broadcast t.not_full;
            Some command
        in
        loop ())

  let write_event t event =
    let line =
      match t.formatter event with
      | line -> Some line
      | exception (Eio.Cancel.Cancelled _ as exn) -> raise exn
      | exception exn ->
          report_error t (Formatter_failed exn);
          None
    in
    match line with
    | None -> `Continue
    | Some line -> (
        match Eio.Flow.copy_string (line ^ "\n") t.flow with
        | () -> `Continue
        | exception (Eio.Cancel.Cancelled _ as exn) -> raise exn
        | exception exn ->
            let error = Write_failed exn in
            close t error;
            report_error t error;
            `Stop)

  let rec run_loop t =
    match take t with
    | None -> ()
    | Some (Flush resolver) ->
        resolve_flush resolver (Ok ());
        run_loop t
    | Some (Event event) -> (
        match write_event t event with `Continue -> run_loop t | `Stop -> ())

  let run t =
    match run_loop t with
    | () -> `Stop_daemon
    | exception (Eio.Cancel.Cancelled _ as exn) ->
        let error = Writer_cancelled exn in
        close ~replace:true t error;
        (match report_error t error with
        | () -> ()
        | exception Eio.Cancel.Cancelled _ -> ()
        | exception _ -> ());
        `Stop_daemon

  let create ~sw ?(capacity = 1024) ?(overflow = Block) ?on_error ~formatter
      flow =
    if capacity <= 0 then invalid_arg "non-positive capacity";
    let t =
      {
        formatter;
        flow;
        overflow;
        on_error;
        capacity;
        queue = Queue.create ();
        mutex = Eio.Mutex.create ();
        not_empty = Eio.Condition.create ();
        not_full = Eio.Condition.create ();
        state = Open;
        dropped_count = 0;
      }
    in
    Eio.Fiber.fork_daemon ~sw (fun () -> run t);
    t
end
