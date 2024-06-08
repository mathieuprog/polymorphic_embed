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
      add(:type, :text, null: true)
      add(:event_id, references(:events))

      add(:channel, :map)
      add(:channel2, :map)
      add(:channel3, :map)
      add(:channel4, :map)
      add(:contexts, :map)
      add(:contexts2, :map)
      add(:contexts3, :map)

      timestamps()
    end

    create table(:todos) do
      add(:reminder_id, references(:reminders), null: false)
      add(:embedded_reminder, :map)
    end
  end
end
