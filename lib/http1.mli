(** Minimal HTTP/1.1 parsing and serialization. *)

type error =
  | Invalid_request_line
  | Unsupported_http_version
  | Unsupported_request_target
  | Malformed_header
  | Invalid_content_length
  | Body_too_large
  | Request_head_too_large
  | Request_head_timeout
  | Unsupported_transfer_encoding

val error_to_string : error -> string
(** [error_to_string error] returns a stable diagnostic string. *)

module Error : sig
  type nonrec t = error

  val pp : Format.formatter -> t -> unit
  val equal : t -> t -> bool
end

type request_head = { meth : Method.t; target : string; headers : Headers.t }
(** Parsed HTTP/1.1 request head without body bytes. *)

val parse_request_head_string : string -> (request_head, error) result
(** [parse_request_head_string raw] parses an HTTP/1.1 request head block.

    [raw] must contain the request line and header lines, without the final
    [CRLF CRLF] separator and without body bytes. *)

val parse_request_string :
  ?max_request_body_size:int -> string -> (Request.t, error) result
(** [parse_request_string ?max_request_body_size raw] parses one complete
    HTTP/1.1 request from [raw]. *)

val serialize_response : Response.t -> string
(** [serialize_response response] serializes [response] with
    [Connection: close]. *)

val response_for_error : error -> Response.t
(** [response_for_error error] returns the first-milestone error response. *)

val content_length : Headers.t -> (int, error) result
(** [content_length headers] validates and returns the request body length. *)
