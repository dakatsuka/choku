(lang dune 3.17)

(name choku)

(generate_opam_files true)

(source
 (github dakatsuka/choku))

(authors "Choku contributors")

(maintainers "Choku contributors")

(license ISC)

(package
 (name choku)
 (synopsis "A pure Eio HTTP server for OCaml 5")
 (description
  "Choku is an OCaml 5 HTTP server project designed around Eio-native direct-style IO.")
 (depends
  (ocaml
   (>= 5.4))
  (dune
   (>= 3.17))
  (eio
   (>= 1.0))
  (eio_main
   (>= 1.0))
  (alcotest
   :with-test)
  (ocamlformat
   :with-dev-setup)))
