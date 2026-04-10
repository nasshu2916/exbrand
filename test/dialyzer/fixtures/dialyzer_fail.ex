defmodule ExBrand.DialyzerTest.FailTypes do
  use ExBrand

  defbrand UserID, :integer
  defbrand OrderID, :integer
end

defmodule ExBrand.DialyzerTest.FailCaller do
  alias ExBrand.DialyzerTest.FailTypes

  @spec accept_user_id(FailTypes.UserID.t()) :: integer()
  def accept_user_id(user_id) do
    FailTypes.UserID.unwrap(user_id)
  end

  @spec wrong_brand() :: integer()
  def wrong_brand do
    {:ok, order_id} = FailTypes.OrderID.new(42)
    accept_user_id(order_id)
  end
end
