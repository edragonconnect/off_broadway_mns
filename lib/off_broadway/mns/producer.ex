defmodule OffBroadway.MNS.Producer do
  @moduledoc """
  A Aliyun MNS producer for Broadway.
  """

  use GenStage

  require Logger

  alias Broadway.{Message, Acknowledger, Producer}
  alias ExAliyun.MNS

  @behaviour Acknowledger
  @behaviour Producer
  @max_batch_size 16
  @queue_url_prefix "queues/"
  @default_receive_opts [number: @max_batch_size]
  @default_retry_receive_message_interval 5_000

  @impl true
  def init(opts) do
    {gen_stage_opts, opts} = Keyword.split(opts, [:buffer_size, :buffer_keep])

    {receive_interval, opts} =
      Keyword.pop(opts, :retry_receive_message_interval, @default_retry_receive_message_interval)

    {queue, opts} =
      Keyword.pop_lazy(opts, :queue, fn -> raise KeyError, key: :queue, term: opts end)

    queue = @queue_url_prefix <> queue

    {receive_opts, opts} = Keyword.pop(opts, :receive_opts, @default_receive_opts)

    prefetch_count = Keyword.fetch!(receive_opts, :number)
    options = producer_options(gen_stage_opts, prefetch_count)

    state = %{
      queue: queue,
      receive_opts: receive_opts,
      receive_interval: receive_interval,
      receive_timer: nil,
      opts: opts,
      demand: 0
    }

    {:producer, state, options}
  end

  @impl true
  def handle_demand(incoming_demand, %{demand: demand} = state) do
    handle_receive_messages(%{state | demand: demand + incoming_demand})
  end

  @impl true
  def handle_info(:receive_messages, %{receive_timer: nil} = state) do
    {:noreply, [], state}
  end

  def handle_info(:receive_messages, state) do
    handle_receive_messages(%{state | receive_timer: nil})
  end

  def handle_info(info, state) do
    Logger.warn("unsupported message: " <> inspect(info))
    {:noreply, [], state}
  end

  @impl Producer
  def prepare_for_draining(%{receive_timer: receive_timer} = state) do
    receive_timer && Process.cancel_timer(receive_timer)
    {:noreply, [], %{state | receive_timer: nil}}
  end

  defp handle_receive_messages(%{receive_timer: nil, demand: demand} = state) when demand > 0 do
    messages = receive_messages_from_mns(state.queue, state.receive_opts)
    new_demand = demand - length(messages)

    receive_timer =
      case messages do
        [] -> schedule_receive_messages(state.receive_interval)
        _ when new_demand <= 0 -> nil
        _ -> schedule_receive_messages(0)
      end

    {:noreply, messages, %{state | demand: new_demand, receive_timer: receive_timer}}
  end

  defp handle_receive_messages(state) do
    {:noreply, [], state}
  end

  defp receive_messages_from_mns(queue, opts) do
    case MNS.receive_message(queue, opts) do
      {:ok, %{body: %{"Messages" => messages}}} ->
        # Logger.info("receive message get:" <> inspect(messages))
        Enum.map(messages, &transform(&1, queue))

      {:error, %{body: %{"Error" => %{"Code" => "MessageNotExist"}}}} ->
        []

      error ->
        Logger.warn("receive message error:" <> inspect(error))

        []
    end
  end

  @compile {:inline, transform: 2}
  defp transform(message, queue) do
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

  defp schedule_receive_messages(interval) do
    Process.send_after(self(), :receive_messages, interval)
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
