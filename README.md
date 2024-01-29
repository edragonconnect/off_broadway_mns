# OffBroadwayMNS

**A Aliyun MNS connector for Broadway**

## Installation

The package can be installed by adding `off_broadway_mns` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:off_broadway_mns, "~> 1.0"}
  ]
end
```

Documentation can be found at <https://hexdocs.pm/off_broadway_mns>.

## Usage

```elixir
defmodule XXX.Pipeline.MNS do
  use Broadway
  require Logger
  alias Broadway.Message

  def start_link(queue) do
    Broadway.start_link(
      __MODULE__,
      name: __MODULE__,
      producer: [
        module: {
          OffBroadway.MNS.Producer,
          queue: queue
        },
        concurrency: 4
      ],
      processors: [
        default: [
          concurrency: 4,
          min_demand: 16,
          max_demand: 32
        ]
      ],
      batchers: [
        default: [
          concurrency: 2,
          batch_size: 200,
          batch_timeout: 3000
        ]
      ]
    )
  end

  @impl true
  def handle_message(_, message, _) do
    Message.update_data(message, fn data ->
      # update data here
      data
    end)
  end

  @impl true
  def handle_batch(_, messages, _batch_info, _context) do
    Enum.map(messages, fn
      message ->
        # add handle code here
        # if failed return: Message.failed(message, "failed reason")
        message
    end)
  end

  @impl true
  def handle_failed(messages, _context) do
    # add handle code here
    messages
  end
end
```