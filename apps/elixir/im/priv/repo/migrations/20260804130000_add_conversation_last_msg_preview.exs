defmodule IM.Repo.Migrations.AddConversationLastMsgPreview do
  use Ecto.Migration

  def change do
    alter table(:conversations) do
      add :last_msg_type, :smallint
      add :last_msg_preview, :string, size: 256
    end
  end
end
