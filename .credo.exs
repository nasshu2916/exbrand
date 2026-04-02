%{
  configs: [
    %{
      name: "default",
      files: %{
        included: ["lib/", "test/", "mix.exs"],
        excluded: [~r"/_build/", ~r"/deps/"]
      },
      strict: true,
      checks: [
        {Credo.Check.Design.TagTODO, false},
        {Credo.Check.Readability.ModuleDoc, false},
        {Credo.Check.Readability.PredicateFunctionNames, false},
        {Credo.Check.Readability.Specs, false},
        {Credo.Check.Refactor.CyclomaticComplexity, false},
        {Credo.Check.Refactor.RedundantWithClauseResult, false},
        {Credo.Check.Refactor.Nesting, max_nesting: 3},
        {Credo.Check.Warning.UnusedEnumOperation, false}
      ]
    }
  ]
}
