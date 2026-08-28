defmodule IM.Services.UserTest do
  use IM.DataCase, async: true

  alias IM.Services.User

  test "provision 幂等建用户" do
    uid = "u_prov_#{System.unique_integer([:positive])}"

    assert {:ok, user} =
             User.provision(%{
               "app_key" => "app_demo",
               "user_id" => uid,
               "password" => "secret"
             })

    assert user.user_id == uid

    assert {:ok, _} =
             User.provision(%{
               "app_key" => "app_demo",
               "user_id" => uid,
               "password" => "newpass"
             })
  end
end
