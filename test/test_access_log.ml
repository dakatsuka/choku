open Alcotest

let request ?(meth = Choku.Method.GET) ?(target = "/")
    ?(headers = Choku.Headers.empty) () =
  Choku.Request.make ~meth ~target ~headers ~body:Choku.Body.empty

let response ?(status = Choku.Status.ok) ?(headers = Choku.Headers.empty) () =
  Choku.Response.make ~headers status

let captured_event ?clock ?mono_clock ?(request = request ())
    ?(response = response ()) () =
  let captured = ref None in
  let middleware =
    Choku.Access_log.middleware ?clock ?mono_clock (fun event ->
        captured := Some event)
  in
  let handler _ = response in
  ignore (middleware handler request : Choku.Response.t);
  match !captured with Some event -> event | None -> fail "missing event"

let emit writer ?request ?response () =
  let event = captured_event ?request ?response () in
  Choku.Access_log.Writer.sink writer event

let test_middleware_records_returned_snapshot () =
  let headers = Choku.Headers.add "x-request" "yes" Choku.Headers.empty in
  let response_headers =
    Choku.Headers.add "x-response" "ok" Choku.Headers.empty
  in
  let request =
    request ~meth:Choku.Method.POST ~target:"/submit?x=1" ~headers ()
  in
  let event =
    captured_event ~request
      ~response:
        (response ~status:Choku.Status.created ~headers:response_headers ())
      ()
  in
  check (module Choku.Method) "method" Choku.Method.POST event.request.meth;
  check string "target" "/submit?x=1" event.request.target;
  check (option string) "request header" (Some "yes")
    (Choku.Headers.get "x-request" event.request.headers);
  check (option string) "protocol" (Some "HTTP/1.1") event.request.protocol;
  match event.outcome with
  | Returned response ->
      check int "status" 201 (Choku.Status.code response.status);
      check (option string) "response header" (Some "ok")
        (Choku.Headers.get "x-response" response.headers)
  | Raised _ | Cancelled -> fail "expected returned outcome"

let test_middleware_records_and_reraises_handler_exception () =
  let exn = Failure "boom" in
  let captured = ref None in
  let middleware =
    Choku.Access_log.middleware (fun event -> captured := Some event)
  in
  let handler _ = raise exn in
  check_raises "handler exception wins" exn (fun () ->
      ignore (middleware handler (request ()) : Choku.Response.t));
  match (!captured : Choku.Access_log.event option) with
  | Some { outcome = Raised raised; _ } ->
      check bool "same exception" true (raised == exn)
  | _ -> fail "expected raised outcome"

let test_middleware_sink_exception_is_swallowed () =
  let middleware =
    Choku.Access_log.middleware (fun _ -> failwith "sink failed")
  in
  let wrapped = middleware (fun _ -> Choku.Response.text "ok") in
  let response = wrapped (request ()) in
  check int "status" 200 (Choku.Status.code (Choku.Response.status response))

let test_middleware_sink_cancellation_is_preserved () =
  let middleware =
    Choku.Access_log.middleware (fun _ -> raise (Eio.Cancel.Cancelled Exit))
  in
  let wrapped = middleware (fun _ -> Choku.Response.text "ok") in
  match wrapped (request ()) with
  | _ -> fail "expected cancellation"
  | exception Eio.Cancel.Cancelled Exit -> ()
  | exception exn ->
      fail ("expected cancellation, got " ^ Printexc.to_string exn)

let test_middleware_records_clock_fields () =
  let clock = Eio_mock.Clock.make () in
  let mono_clock = Eio_mock.Clock.Mono.make () in
  Eio_mock.Clock.set_time clock 971186136.0;
  Eio_mock.Clock.Mono.set_time mono_clock (Mtime.of_uint64_ns 10L);
  let captured = ref None in
  let middleware =
    Choku.Access_log.middleware ~clock ~mono_clock (fun event ->
        captured := Some event)
  in
  let handler _ =
    Eio_mock.Clock.Mono.set_time mono_clock (Mtime.of_uint64_ns 42L);
    Choku.Response.text "ok"
  in
  ignore (middleware handler (request ()) : Choku.Response.t);
  match (!captured : Choku.Access_log.event option) with
  | Some event ->
      check
        (option (float 0.0))
        "started_at" (Some 971186136.0) event.started_at;
      check (option int64) "duration_ns" (Some 32L) event.duration_ns
  | None -> fail "missing event"

let test_status_helper () =
  let returned =
    captured_event ~response:(response ~status:Choku.Status.accepted ()) ()
  in
  check (option int) "returned" (Some 202)
    (Option.map Choku.Status.code (Choku.Access_log.status returned));
  let raised =
    let captured = ref None in
    let middleware =
      Choku.Access_log.middleware (fun event -> captured := Some event)
    in
    let handler _ = failwith "boom" in
    (try ignore (middleware handler (request ()) : Choku.Response.t)
     with Failure message when String.equal message "boom" -> ());
    match !captured with Some event -> event | None -> fail "missing event"
  in
  check (option int) "raised" (Some 500)
    (Option.map Choku.Status.code (Choku.Access_log.status raised))

let test_format_clf_style () =
  let clock = Eio_mock.Clock.make () in
  Eio_mock.Clock.set_time clock 971186136.0;
  let event =
    captured_event ~clock
      ~request:(request ~target:"/hello\"x\\y" ())
      ~response:(response ~status:Choku.Status.created ())
      ()
  in
  check string "clf"
    "- - - [10/Oct/2000:13:55:36 +0000] \"GET /hello\\\"x\\\\y HTTP/1.1\" 201 -"
    (Choku.Access_log.format_clf_style event)

let test_format_clf_style_without_timestamp () =
  let event = captured_event () in
  check string "clf" "- - - - \"GET / HTTP/1.1\" 200 -"
    (Choku.Access_log.format_clf_style event)

let test_format_clf_style_for_raised_outcome () =
  let captured = ref None in
  let middleware =
    Choku.Access_log.middleware (fun event -> captured := Some event)
  in
  let handler _ = failwith "boom" in
  (try ignore (middleware handler (request ()) : Choku.Response.t)
   with Failure message when String.equal message "boom" -> ());
  let event =
    match !captured with Some event -> event | None -> fail "missing event"
  in
  check string "clf" "- - - - \"GET / HTTP/1.1\" 500 -"
    (Choku.Access_log.format_clf_style event)

let test_writer_writes_newline_and_flushes () =
  Eio_main.run @@ fun _env ->
  Eio.Switch.run @@ fun sw ->
  let buffer = Buffer.create 64 in
  let writer =
    Choku.Access_log.Writer.create ~sw
      ~formatter:Choku.Access_log.format_clf_style
      (Eio.Flow.buffer_sink buffer)
  in
  emit writer ();
  check (result unit reject) "flush" (Ok ())
    (Choku.Access_log.Writer.flush writer);
  check string "output" "- - - - \"GET / HTTP/1.1\" 200 -\n"
    (Buffer.contents buffer)

let test_writer_formatter_failure_continues () =
  Eio_main.run @@ fun _env ->
  Eio.Switch.run @@ fun sw ->
  let buffer = Buffer.create 64 in
  let errors = ref [] in
  let writer =
    Choku.Access_log.Writer.create ~sw
      ~on_error:(fun error -> errors := error :: !errors)
      ~formatter:(fun event ->
        if String.equal event.request.target "/bad" then failwith "bad format";
        event.request.target)
      (Eio.Flow.buffer_sink buffer)
  in
  emit writer ~request:(request ~target:"/bad" ()) ();
  emit writer ~request:(request ~target:"/ok" ()) ();
  check (result unit reject) "flush" (Ok ())
    (Choku.Access_log.Writer.flush writer);
  check string "output" "/ok\n" (Buffer.contents buffer);
  match !errors with
  | [ Choku.Access_log.Writer.Formatter_failed (Failure message) ]
    when String.equal message "bad format" ->
      ()
  | _ -> fail "expected one formatter error"

let test_writer_drop_overflow_counts_dropped_events () =
  Eio_main.run @@ fun _env ->
  Eio.Switch.run @@ fun sw ->
  let buffer = Buffer.create 64 in
  let writer =
    Choku.Access_log.Writer.create ~sw ~capacity:1
      ~overflow:Choku.Access_log.Writer.Drop
      ~formatter:(fun event -> event.request.target)
      (Eio.Flow.buffer_sink buffer)
  in
  emit writer ~request:(request ~target:"/one" ()) ();
  emit writer ~request:(request ~target:"/two" ()) ();
  check int "dropped" 1 (Choku.Access_log.Writer.dropped_count writer);
  check (result unit reject) "flush" (Ok ())
    (Choku.Access_log.Writer.flush writer);
  check string "output" "/one\n" (Buffer.contents buffer)

let test_writer_block_overflow_preserves_events () =
  Eio_main.run @@ fun _env ->
  Eio.Switch.run @@ fun sw ->
  let buffer = Buffer.create 64 in
  let writer =
    Choku.Access_log.Writer.create ~sw ~capacity:1
      ~overflow:Choku.Access_log.Writer.Block
      ~formatter:(fun event -> event.request.target)
      (Eio.Flow.buffer_sink buffer)
  in
  emit writer ~request:(request ~target:"/one" ()) ();
  emit writer ~request:(request ~target:"/two" ()) ();
  check int "dropped" 0 (Choku.Access_log.Writer.dropped_count writer);
  check (result unit reject) "flush" (Ok ())
    (Choku.Access_log.Writer.flush writer);
  check string "output" "/one\n/two\n" (Buffer.contents buffer)

module Failing_sink = struct
  type t = unit

  let single_write () _ = failwith "write failed"
  let copy t ~src = Eio.Flow.Pi.simple_copy ~single_write t ~src
end

let failing_sink () = Eio.Resource.T ((), Eio.Flow.Pi.sink (module Failing_sink))

let test_writer_write_failure_closes_writer () =
  Eio_main.run @@ fun _env ->
  Eio.Switch.run @@ fun sw ->
  let errors = ref [] in
  let writer =
    Choku.Access_log.Writer.create ~sw
      ~on_error:(fun error -> errors := error :: !errors)
      ~formatter:(fun event -> event.request.target)
      (failing_sink ())
  in
  emit writer ~request:(request ~target:"/one" ()) ();
  (match Choku.Access_log.Writer.flush writer with
  | Error (Choku.Access_log.Writer.Write_failed (Failure message))
    when String.equal message "write failed" ->
      ()
  | Ok () -> fail "expected write failure"
  | Error _ -> fail "expected write failure error");
  emit writer ~request:(request ~target:"/after-close" ()) ();
  check int "dropped" 0 (Choku.Access_log.Writer.dropped_count writer);
  match !errors with
  | [ Choku.Access_log.Writer.Write_failed (Failure message) ]
    when String.equal message "write failed" ->
      ()
  | _ -> fail "expected one write error"

let test_writer_write_failure_closes_before_on_error () =
  Eio_main.run @@ fun _env ->
  Eio.Switch.run @@ fun sw ->
  let writer_ref = ref None in
  let callback_flush = ref None in
  let writer =
    Choku.Access_log.Writer.create ~sw
      ~on_error:(fun _ ->
        match !writer_ref with
        | None -> fail "missing writer"
        | Some writer ->
            callback_flush := Some (Choku.Access_log.Writer.flush writer))
      ~formatter:(fun event -> event.request.target)
      (failing_sink ())
  in
  writer_ref := Some writer;
  emit writer ~request:(request ~target:"/one" ()) ();
  (match Choku.Access_log.Writer.flush writer with
  | Error (Choku.Access_log.Writer.Write_failed (Failure message))
    when String.equal message "write failed" ->
      ()
  | Ok () -> fail "expected write failure"
  | Error _ -> fail "expected write failure error");
  match !callback_flush with
  | Some (Error (Choku.Access_log.Writer.Write_failed (Failure message)))
    when String.equal message "write failed" ->
      ()
  | Some (Ok ()) -> fail "expected callback flush write failure"
  | Some (Error _) -> fail "expected callback flush write failure error"
  | None -> fail "missing callback flush result"

let test_writer_cancellation_closes_writer () =
  let writer = ref None in
  let () =
    Eio_main.run @@ fun _env ->
    Eio.Switch.run @@ fun sw ->
    writer :=
      Some
        (Choku.Access_log.Writer.create ~sw
           ~formatter:Choku.Access_log.format_clf_style
           (Eio.Flow.buffer_sink (Buffer.create 0)))
  in
  match !writer with
  | None -> fail "missing writer"
  | Some writer -> (
      match Choku.Access_log.Writer.flush writer with
      | Error (Choku.Access_log.Writer.Writer_cancelled _) -> ()
      | Ok () -> fail "expected writer cancellation"
      | Error _ -> fail "expected writer cancellation error")

let test_writer_rejects_invalid_capacity () =
  Eio_main.run @@ fun _env ->
  Eio.Switch.run @@ fun sw ->
  check_raises "invalid capacity" (Invalid_argument "non-positive capacity")
    (fun () ->
      ignore
        (Choku.Access_log.Writer.create ~sw ~capacity:0
           ~formatter:Choku.Access_log.format_clf_style
           (Eio.Flow.buffer_sink (Buffer.create 0))
          : Choku.Access_log.Writer.t))

let () =
  run "access_log"
    [
      ( "middleware",
        [
          test_case "records returned snapshot" `Quick
            test_middleware_records_returned_snapshot;
          test_case "records and reraises handler exception" `Quick
            test_middleware_records_and_reraises_handler_exception;
          test_case "sink exception is swallowed" `Quick
            test_middleware_sink_exception_is_swallowed;
          test_case "sink cancellation is preserved" `Quick
            test_middleware_sink_cancellation_is_preserved;
          test_case "records clock fields" `Quick
            test_middleware_records_clock_fields;
          test_case "status helper" `Quick test_status_helper;
        ] );
      ( "formatter",
        [
          test_case "formats CLF-style line" `Quick test_format_clf_style;
          test_case "formats missing timestamp" `Quick
            test_format_clf_style_without_timestamp;
          test_case "formats raised outcome" `Quick
            test_format_clf_style_for_raised_outcome;
        ] );
      ( "writer",
        [
          test_case "writes newline and flushes" `Quick
            test_writer_writes_newline_and_flushes;
          test_case "formatter failure continues" `Quick
            test_writer_formatter_failure_continues;
          test_case "drop overflow counts dropped events" `Quick
            test_writer_drop_overflow_counts_dropped_events;
          test_case "block overflow preserves events" `Quick
            test_writer_block_overflow_preserves_events;
          test_case "write failure closes writer" `Quick
            test_writer_write_failure_closes_writer;
          test_case "write failure closes before on_error" `Quick
            test_writer_write_failure_closes_before_on_error;
          test_case "cancellation closes writer" `Quick
            test_writer_cancellation_closes_writer;
          test_case "rejects invalid capacity" `Quick
            test_writer_rejects_invalid_capacity;
        ] );
    ]
