defmodule ExBrand.DialyzerTest.PassTypes do
  use ExBrand

  defbrand UserID, :integer
  defbrand OrderID, :integer
end

defmodule ExBrand.DialyzerTest.PassCaller do
  alias ExBrand.DialyzerTest.PassTypes

  @spec accept_user_id(PassTypes.UserID.t()) :: integer()
  def accept_user_id(user_id) do
    PassTypes.UserID.unwrap(user_id)
  end

  @spec correct_usage() :: integer()
  def correct_usage do
    {:ok, user_id} = PassTypes.UserID.new(42)
    accept_user_id(user_id)
  end
end
