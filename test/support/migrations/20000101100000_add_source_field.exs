defmodule PolymorphicEmbed.AddSourceField do
  use Ecto.Migration

  def change do
    alter table(:reminders) do
      add(:source, :map)
      add(:reference, :map)
    end
  end
end
