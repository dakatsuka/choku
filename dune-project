(lang dune 3.17)

(name camelio)

(generate_opam_files true)

(source
 (github dakatsuka/camelio))

(authors "Camelio contributors")

(maintainers "Camelio contributors")

(license ISC)

(package
 (name camelio)
 (synopsis "A pure Eio HTTP server for OCaml 5")
 (description
  "Camelio is an OCaml 5 HTTP server project designed around Eio-native direct-style IO.")
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
