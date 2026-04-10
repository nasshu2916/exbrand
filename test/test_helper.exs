Code.require_file("../test_support/ex_brand_support.ex", __DIR__)
Code.require_file("support/dialyzer_helper.ex", __DIR__)

ExUnit.start(exclude: [:dialyzer])
