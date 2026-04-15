defmodule MyApp.Types do
  use ExBrand

  defbrand UserID, :integer
  defbrand OrderID, :integer
  defbrand CustomerID, :integer

  defbrand Email, {:string, validate: &String.contains?(&1, "@"), error: :invalid_email}
end

alias MyApp.Types

{:ok, user_id} = MyApp.Types.UserID.new(1)
