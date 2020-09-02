defmodule OffBroadway.MNS.Producer do
  @moduledoc """
  A Aliyun MNS producer for Broadway.
  """

  use GenStage

  require Logger

  alias Broadway.{Message, Acknowledger, Producer}
  alias ExAliyun.MNS
  alias OffBroadway.MNS.Receiver

  @behaviour Acknowledger
  @behaviour Producer
  @max_batch_size 16
  @queue_url_prefix "queues/"
  @default_receive_opts [number: @max_batch_size, wait_time_seconds: 30]
  @default_retry_receive_message_interval 1_000

  @impl true
  def init(opts) do
    {gen_stage_opts, opts} = Keyword.split(opts, [:buffer_size, :buffer_keep])

    {retry_receive_message_interval, opts} =
      Keyword.pop(opts, :retry_receive_message_interval, @default_retry_receive_message_interval)

    {queue, opts} =
      Keyword.pop_lazy(opts, :queue, fn -> raise KeyError, key: :queue, term: opts end)

    queue = @queue_url_prefix <> queue

    {receive_opts, opts} = Keyword.pop(opts, :receive_opts, @default_receive_opts)

    prefetch_count = Keyword.fetch!(receive_opts, :number)
    options = producer_options(gen_stage_opts, prefetch_count)

    {:ok, receiver} = Receiver.start_link(queue, receive_opts, retry_receive_message_interval)

    state = %{
      queue: queue,
      receive_opts: receive_opts,
      retry_receive_message_interval: retry_receive_message_interval,
      receiver: receiver,
      opts: opts,
      demand: 0
    }

    {:producer, state, options}
  end

  @impl true
  def handle_demand(incoming_demand, state = %{demand: old_demand}) do
    case old_demand + incoming_demand do
      demand when old_demand <= 0 and demand >= 0 ->
        Receiver.start_receive(state.receiver)
        {:noreply, [], %{state | demand: demand}}

      demand ->
        {:noreply, [], %{state | demand: demand}}
    end
  end

  @impl true
  def handle_info({:receive, messages}, state = %{queue: queue, demand: old_demand}) do
    messages =
      Enum.map(
        messages,
        fn message ->
          {data, metadata} =
            Map.pop_lazy(
              message,
              "MessageBody",
              fn ->
                raise KeyError, key: "MessageBody", term: message
              end
            )

          %Message{
            data: data,
            metadata: metadata,
            acknowledger: {__MODULE__, _ack_ref = queue, []}
          }
        end
      )

    demand = old_demand - length(messages)

    if demand <= 0 do
      Receiver.stop_receive(state.receiver)
    end

    {:noreply, messages, %{state | demand: demand}}
  end

  def handle_info(info, state) do
    Logger.warn("unsupported message: " <> inspect(info))
    {:noreply, [], state}
  end

  @impl Acknowledger
  def ack(_ack_ref = queue, successful, _failed) do
    # only successful messages ask to delete
    # failed messages will auto retry by MNS
    Stream.chunk_every(successful, @max_batch_size)
    |> Enum.each(fn messages ->
      receipt_handles =
        Enum.map(
          messages,
          fn message ->
            message.metadata["ReceiptHandle"]
          end
        )

      MNS.batch_delete_message(queue, receipt_handles)
    end)

    :ok
  end

  defp producer_options(opts, 0) do
    if opts[:buffer_size] do
      opts
    else
      raise ArgumentError, ":prefetch_count is 0, specify :buffer_size explicitly"
    end
  end

  defp producer_options(opts, prefetch_count) do
    Keyword.put_new(opts, :buffer_size, prefetch_count * 5)
  end
end
