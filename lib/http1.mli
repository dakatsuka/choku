(** Minimal HTTP/1.1 parsing and serialization. *)

type error =
  | Invalid_request_line
  | Unsupported_http_version
  | Unsupported_request_target
  | Malformed_header
  | Invalid_content_length
  | Body_too_large
  | Malformed_chunked_body
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

(** HTTP/1.1 request body framing selected from Content-Length or
    Transfer-Encoding. *)
type request_body_framing = Fixed of int | Chunked

val parse_request_head_string : string -> (request_head, error) result
(** [parse_request_head_string raw] parses an HTTP/1.1 request head block.

    [raw] must contain the request line and header lines, without the final
    [CRLF CRLF] separator and without body bytes. *)

val parse_request_string :
  ?max_request_body_size:int -> string -> (Request.t, error) result
(** [parse_request_string ?max_request_body_size raw] parses one complete
    HTTP/1.1 request from [raw]. *)

val serialize_response :
  ?include_body:bool -> ?connection:string -> Response.t -> string
(** [serialize_response ?include_body ?connection response] serializes
    [response] with a [Connection] header.

    [connection] defaults to ["close"].

    [include_body] defaults to [true]. When [false], the serialized
    [Content-Length] still reflects [response]'s body, but no body bytes are
    appended. *)

val response_for_error : error -> Response.t
(** [response_for_error error] returns the HTTP/1.1 error response for a request
    parsing or reading failure. *)

val content_length : Headers.t -> (int, error) result
(** [content_length headers] validates and returns the request body length. *)

val request_body_framing : Headers.t -> (request_body_framing, error) result
(** [request_body_framing headers] validates request body framing. *)
