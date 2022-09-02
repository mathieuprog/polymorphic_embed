# Used by "mix format"
locals_with_parens = [
  polymorphic_embeds_one: 2,
  polymorphic_embeds_many: 2
]

[
  import_deps: [:ecto],
  inputs: ["{mix,.formatter}.exs", "{config,lib,test}/**/*.{ex,exs}"],
  locals_without_parens: locals_with_parens,
  export: [
    locals_with_parens: locals_with_parens
  ]
]
