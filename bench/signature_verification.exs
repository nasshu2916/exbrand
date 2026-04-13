# Benchmark: signature_verification on vs off
#
# signature_verification は compile-time config なので、
# 別々のモジュールとして on/off それぞれの brand を定義する。
#
# Usage:
#   SIGNATURE_VERIFICATION=off mix run bench/signature_verification.exs
#   SIGNATURE_VERIFICATION=on  mix run bench/signature_verification.exs
#   SIGNATURE_VERIFICATION=both mix run bench/signature_verification.exs  (default)

Mix.Task.run("app.start")

mode = System.get_env("SIGNATURE_VERIFICATION", "both")

# --- signature_verification: false のモジュール定義 ---
Application.put_env(:ex_brand, :signature_verification, false)

defmodule ExBrand.Bench.Sig.OffTypes do
  use ExBrand

  defbrand UserID, :integer
  defbrand Email, {:string, validate: &String.contains?(&1, "@"), error: :invalid_email}
end

# --- signature_verification: true のモジュール定義 ---
Application.put_env(:ex_brand, :signature_verification, true)

defmodule ExBrand.Bench.Sig.OnTypes do
  use ExBrand

  defbrand UserID, :integer
  defbrand Email, {:string, validate: &String.contains?(&1, "@"), error: :invalid_email}
end

# 元に戻す
Application.put_env(:ex_brand, :signature_verification, false)

# テストデータ
user_id = 42
email = "user@example.com"

# 事前に brand 値を作成 (unwrap / brand? 用)
{:ok, brand_uid_off} = ExBrand.Bench.Sig.OffTypes.UserID.new(user_id)
{:ok, brand_uid_on} = ExBrand.Bench.Sig.OnTypes.UserID.new(user_id)
{:ok, brand_email_off} = ExBrand.Bench.Sig.OffTypes.Email.new(email)
{:ok, brand_email_on} = ExBrand.Bench.Sig.OnTypes.Email.new(email)

# ベンチマーク定義
benchmarks_off = %{
  "new/1 UserID (sig: off)" => fn ->
    {:ok, _} = ExBrand.Bench.Sig.OffTypes.UserID.new(user_id)
  end,
  "new/1 Email (sig: off)" => fn ->
    {:ok, _} = ExBrand.Bench.Sig.OffTypes.Email.new(email)
  end,
  "unwrap/1 UserID (sig: off)" => fn ->
    _ = ExBrand.Bench.Sig.OffTypes.UserID.unwrap(brand_uid_off)
  end,
  "unwrap/1 Email (sig: off)" => fn ->
    _ = ExBrand.Bench.Sig.OffTypes.Email.unwrap(brand_email_off)
  end,
  "brand?/1 UserID (sig: off)" => fn ->
    ExBrand.Bench.Sig.OffTypes.UserID.brand?(brand_uid_off)
  end,
  "brand?/1 Email (sig: off)" => fn ->
    ExBrand.Bench.Sig.OffTypes.Email.brand?(brand_email_off)
  end
}

benchmarks_on = %{
  "new/1 UserID (sig: on)" => fn ->
    {:ok, _} = ExBrand.Bench.Sig.OnTypes.UserID.new(user_id)
  end,
  "new/1 Email (sig: on)" => fn ->
    {:ok, _} = ExBrand.Bench.Sig.OnTypes.Email.new(email)
  end,
  "unwrap/1 UserID (sig: on)" => fn ->
    _ = ExBrand.Bench.Sig.OnTypes.UserID.unwrap(brand_uid_on)
  end,
  "unwrap/1 Email (sig: on)" => fn ->
    _ = ExBrand.Bench.Sig.OnTypes.Email.unwrap(brand_email_on)
  end,
  "brand?/1 UserID (sig: on)" => fn ->
    ExBrand.Bench.Sig.OnTypes.UserID.brand?(brand_uid_on)
  end,
  "brand?/1 Email (sig: on)" => fn ->
    ExBrand.Bench.Sig.OnTypes.Email.brand?(brand_email_on)
  end
}

benchmarks =
  case mode do
    "off" -> benchmarks_off
    "on" -> benchmarks_on
    _ -> Map.merge(benchmarks_off, benchmarks_on)
  end

IO.puts("""
\n=== Signature Verification Benchmark ===
Mode: #{mode}
Comparing: new/1, unwrap/1, brand?/1
  - sig: off → struct has no __signature__ field, __valid_signature__ always returns true
  - sig: on  → struct has __signature__ field, phash2 computed on every new/unwrap/brand?
""")

Benchee.run(
  benchmarks,
  time: 3,
  memory_time: 1,
  reduction_time: 1,
  print: [fast_warning: false]
)
