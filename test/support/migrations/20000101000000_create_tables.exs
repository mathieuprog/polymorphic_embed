defmodule PolymorphicEmbed.CreateTables do
  use Ecto.Migration

  def change do
    create table(:events) do
      add(:embedded_reminders, :map)
      timestamps()
    end

    create table(:reminders) do
      add(:date, :utc_datetime, null: false)
      add(:text, :text, null: false)
      add(:event_id, references(:events))

      add(:channel, :map)
      add(:contexts, :map)
      add(:contexts2, :map)

      timestamps()
    end

    create table(:todos) do
      add(:reminder_id, references(:reminders), null: false)
      add(:embedded_reminder, :map)
    end
  end
end
