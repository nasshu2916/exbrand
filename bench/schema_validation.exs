Mix.Task.run("app.start")

defmodule ExBrand.Bench.Primitive do
  def validate_user_id(value) when is_integer(value), do: {:ok, value}
  def validate_user_id(_value), do: {:error, :invalid_type}

  def validate_email(value) when is_binary(value) do
    if String.contains?(value, "@") do
      {:ok, value}
    else
      {:error, :invalid_email}
    end
  end

  def validate_email(_value), do: {:error, :invalid_type}
end

defmodule ExBrand.Bench.Types do
  use ExBrand

  defbrand UserID, :integer
  defbrand Email, {:string, validate: &String.contains?(&1, "@"), error: :invalid_email}
end

defmodule ExBrand.Bench.AddressSchema do
  use ExBrand.Schema

  field(:city, :string)
  field(:zip, {:string, min_length: 5, max_length: 5})
end

defmodule ExBrand.Bench.UserSchema do
  use ExBrand.Schema

  field(:user_id, ExBrand.Bench.Types.UserID)
  field(:email, ExBrand.Bench.Types.Email)
  field(:age, {:integer, minimum: 18})
  field(:nickname, {:string, optional: true})
  field(:status, {:string, default: "active"})
  field(:contact_email, {ExBrand.Bench.Types.Email, field: "contactEmail"})
  field(:address, ExBrand.Bench.AddressSchema)
  field(:tags, {[{:string, min_length: 2}], min_items: 1, unique_items: true, optional: true})
  field(:published_at, {:string, format: :datetime, optional: true})
end

user_input = %{
  "contactEmail" => "contact@example.com",
  address: %{city: "Tokyo", zip: "15000"},
  user_id: 1,
  email: "user@example.com",
  age: 20,
  tags: ["elixir", "otp"],
  published_at: "2026-04-02T12:34:56Z"
}

raw_schema = ExBrand.Bench.UserSchema.__schema__()
user_id = 1
email = "user@example.com"

defmodule ExBrand.Bench.Config do
  @iterations 100
  def iterations, do: @iterations
end

Benchee.run(
  %{
    "brand user_id new/1" => fn ->
      Enum.each(1..ExBrand.Bench.Config.iterations(), fn _ ->
        {:ok, _brand} = ExBrand.Bench.Types.UserID.new(user_id)
      end)
    end,
    "brand user_id unsafe_new/1" => fn ->
      Enum.each(1..ExBrand.Bench.Config.iterations(), fn _ ->
        {:ok, _brand} = ExBrand.Bench.Types.UserID.unsafe_new(user_id)
      end)
    end,
    "primitive user_id validate" => fn ->
      Enum.each(1..ExBrand.Bench.Config.iterations(), fn _ ->
        {:ok, _value} = ExBrand.Bench.Primitive.validate_user_id(user_id)
      end)
    end,
    "brand email new/1" => fn ->
      Enum.each(1..ExBrand.Bench.Config.iterations(), fn _ ->
        {:ok, _brand} = ExBrand.Bench.Types.Email.new(email)
      end)
    end,
    "brand email unsafe_new/1" => fn ->
      Enum.each(1..ExBrand.Bench.Config.iterations(), fn _ ->
        {:ok, _brand} = ExBrand.Bench.Types.Email.unsafe_new(email)
      end)
    end,
    "primitive email validate" => fn ->
      Enum.each(1..ExBrand.Bench.Config.iterations(), fn _ ->
        {:ok, _value} = ExBrand.Bench.Primitive.validate_email(email)
      end)
    end,
    "module schema validate/1" => fn ->
      Enum.each(1..ExBrand.Bench.Config.iterations(), fn _ ->
        {:ok, _result} = ExBrand.Bench.UserSchema.validate(user_input)
      end)
    end,
    "raw schema validate/2" => fn ->
      Enum.each(1..ExBrand.Bench.Config.iterations(), fn _ ->
        {:ok, _result} = ExBrand.Schema.validate(user_input, raw_schema)
      end)
    end
  },
  time: 3,
  memory_time: 1,
  print: [fast_warning: false]
)
