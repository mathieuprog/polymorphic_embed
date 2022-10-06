defmodule PolymorphicEmbed.AddAttachments do
  use Ecto.Migration

  def change do
    alter table(:reminders) do
      add(:attachment, :map)
    end
  end
end
