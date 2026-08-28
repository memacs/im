defmodule IM.Auth.TokenCacheTest do
  use IM.DataCase, async: false

  alias IM.Auth.{Token, TokenCache}
  alias IM.Cache.Memory
  alias IM.Stores.AccessTokenStore

  setup do
    Memory.reset!()
    :ok
  end

  test "首次 verify 后写入缓存，revoke_hash 立即失效" do
    %{token: token, app_key: app_key, user_id: user_id, device_id: device_id} =
      IM.AuthFixtures.login!()

    hash = Token.hash(token)
    assert :miss = TokenCache.lookup(hash)

    assert {:ok, _} = IM.Auth.verify_token(token)
    assert {:ok, cached} = TokenCache.lookup(hash)
    assert cached.app_key == app_key
    assert cached.user_id == user_id
    assert cached.device_id == device_id

    :ok = AccessTokenStore.revoke_hash(hash)
    assert {:error, :revoked} = TokenCache.lookup(hash)
    assert {:error, _} = IM.Auth.verify_token(token)
  end

  test "revoke_device 使已缓存 token 在下次 lookup 时 miss" do
    %{token: token, app_key: app_key, user_id: user_id, device_id: device_id} =
      IM.AuthFixtures.login!()

    hash = Token.hash(token)
    assert {:ok, _} = IM.Auth.verify_token(token)
    assert {:ok, _} = TokenCache.lookup(hash)

    :ok = AccessTokenStore.revoke_device(app_key, user_id, device_id)
    assert :miss = TokenCache.lookup(hash)
    assert {:error, _} = IM.Auth.verify_token(token)
  end
end
