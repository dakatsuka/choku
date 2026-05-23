(** HTTP response status values. *)

type t

val code : t -> int
(** [code t] returns the three-digit status code. *)

val reason : t -> string
(** [reason t] returns the reason phrase. Unknown valid codes have an empty
    reason phrase. *)

val of_code : int -> t
(** [of_code code] returns a status for [code].

    @raise Invalid_argument if [code] is outside 100 through 599. *)

val continue_ : t
val switching_protocols : t
val processing : t
val early_hints : t
val ok : t
val created : t
val accepted : t
val non_authoritative_information : t
val no_content : t
val reset_content : t
val partial_content : t
val multi_status : t
val already_reported : t
val im_used : t
val multiple_choices : t
val moved_permanently : t
val found : t
val see_other : t
val not_modified : t
val use_proxy : t
val temporary_redirect : t
val permanent_redirect : t
val bad_request : t
val unauthorized : t
val payment_required : t
val forbidden : t
val not_found : t
val method_not_allowed : t
val not_acceptable : t
val proxy_authentication_required : t
val request_timeout : t
val conflict : t
val gone : t
val length_required : t
val precondition_failed : t
val payload_too_large : t
val uri_too_long : t
val unsupported_media_type : t
val range_not_satisfiable : t
val expectation_failed : t
val im_a_teapot : t
val misdirected_request : t
val unprocessable_content : t
val locked : t
val failed_dependency : t
val too_early : t
val upgrade_required : t
val precondition_required : t
val too_many_requests : t
val request_header_fields_too_large : t
val unavailable_for_legal_reasons : t
val internal_server_error : t
val not_implemented : t
val bad_gateway : t
val service_unavailable : t
val gateway_timeout : t
val http_version_not_supported : t
val variant_also_negotiates : t
val insufficient_storage : t
val loop_detected : t
val not_extended : t
val network_authentication_required : t
