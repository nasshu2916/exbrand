defmodule ExBrand.DialyzerTest do
  use ExUnit.Case

  @moduletag :dialyzer

  @fixtures_dir Path.join([__DIR__, "..", "dialyzer", "fixtures"]) |> Path.expand()

  describe "brand type safety" do
    test "異なる brand 型の渡し間違いで Dialyzer 警告が出る" do
      warnings =
        @fixtures_dir
        |> Path.join("dialyzer_fail.ex")
        |> ExBrand.DialyzerHelper.compile_and_analyze()

      assert warnings != [],
             "Expected Dialyzer warnings for wrong brand type usage, but got none"

      warning_text = Enum.join(warnings, "\n")

      assert warning_text =~ "FailCaller" or warning_text =~ "accept_user_id",
             "Expected warning to mention the mismatched function call, got:\n#{warning_text}"
    end

    test "正しい brand 型の使用で Dialyzer 警告が出ない" do
      warnings =
        @fixtures_dir
        |> Path.join("dialyzer_pass.ex")
        |> ExBrand.DialyzerHelper.compile_and_analyze()

      assert warnings == [],
             "Expected no Dialyzer warnings for correct brand usage, but got:\n#{Enum.join(warnings, "\n")}"
    end
  end
end
