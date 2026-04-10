defmodule ExBrand.DialyzerHelper do
  @moduledoc false

  @doc """
  指定されたフィクスチャファイルをコンパイルし、Dialyzer で解析して警告を返す。

  1. フィクスチャを BEAM にコンパイル
  2. ExBrand ライブラリ本体の BEAM + フィクスチャの BEAM を解析対象に
  3. プロジェクト PLT を使って `:dialyzer.run/1` を実行
  4. フィクスチャファイル由来の警告のみをフィルタして返す
  """
  @spec compile_and_analyze(Path.t()) :: [String.t()]
  def compile_and_analyze(fixture_path) do
    tmp_dir = prepare_tmp_dir()

    try do
      beam_files = compile_fixture(fixture_path, tmp_dir)
      project_beams = project_beam_files()
      plt_path = find_plt()

      warnings = run_dialyzer(beam_files ++ project_beams, plt_path)
      filter_fixture_warnings(warnings, beam_files)
    after
      File.rm_rf!(tmp_dir)
    end
  end

  defp prepare_tmp_dir do
    tmp_dir =
      Path.join([
        Mix.Project.build_path(),
        "dialyzer_test_#{System.unique_integer([:positive])}"
      ])

    File.mkdir_p!(tmp_dir)
    tmp_dir
  end

  defp compile_fixture(fixture_path, output_dir) do
    {:ok, modules, _warnings} =
      Kernel.ParallelCompiler.compile_to_path(
        [fixture_path],
        output_dir,
        return_diagnostics: true
      )

    Enum.map(modules, fn module ->
      Path.join(output_dir, "#{module}.beam") |> to_charlist()
    end)
  end

  defp project_beam_files do
    ebin_dir = Path.join([Mix.Project.build_path(), "lib", "ex_brand", "ebin"])

    ebin_dir
    |> File.ls!()
    |> Enum.filter(&String.ends_with?(&1, ".beam"))
    |> Enum.map(&(Path.join(ebin_dir, &1) |> to_charlist()))
  end

  defp find_plt do
    # mix.exs の dialyzer 設定に plt_local_path: "priv/plts" が指定されている
    plt_dir =
      Path.join([File.cwd!(), "priv", "plts"])
      |> Path.expand()

    plt_file =
      plt_dir
      |> File.ls!()
      |> Enum.find(&String.ends_with?(&1, "_deps-test.plt"))

    unless plt_file do
      raise "PLT file not found in #{plt_dir}. Run `mix dialyzer` first to build the PLT."
    end

    Path.join(plt_dir, plt_file) |> to_charlist()
  end

  defp run_dialyzer(beam_files, plt_path) do
    :dialyzer.run(
      analysis_type: :succ_typings,
      files: beam_files,
      init_plt: plt_path,
      warnings: [:error_handling, :missing_return, :underspecs]
    )
  end

  defp filter_fixture_warnings(warnings, fixture_beams) do
    fixture_modules =
      fixture_beams
      |> Enum.map(fn beam_charlist ->
        beam_charlist
        |> to_string()
        |> Path.basename(".beam")
        |> String.to_atom()
      end)
      |> MapSet.new()

    warnings
    |> Enum.filter(fn warning ->
      {_tag, {module, _line}, _msg} = warning
      module in fixture_modules
    end)
    |> Enum.map(&:dialyzer.format_warning(&1))
    |> Enum.map(&to_string/1)
  end
end
