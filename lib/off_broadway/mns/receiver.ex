defmodule OffBroadway.MNS.Receiver do
  @moduledoc """
  A Aliyun MNS Receiver for receive messages and send to Producer.
  state in [:receiving, :resting, :stopping]

  State change flow:
       ┌---------- start ---------┐
       |                          |
       |                          ▼
  |:stopping| ◀--- stop --- |:receiving| --- receive_timeout ---▶ |:resting|
                                  ▲                                    |
                                  |                                    |
                                  └---------- state_timeout -----------┘
  """

  use GenStateMachine
  require Logger
  alias ExAliyun.MNS

  @default_retry_receive_message_interval 1_000

  def start_link(
        queue,
        receive_opts \\ [],
        retry_receive_message_interval \\ @default_retry_receive_message_interval
      ) do
    data = %{
      queue: queue,
      receive_opts: receive_opts,
      parent: self(),
      retry_receive_message_interval: retry_receive_message_interval
    }

    GenStateMachine.start_link(__MODULE__, {:stopping, data})
  end

  def start_receive(pid) do
    GenStateMachine.cast(pid, :start)
  end

  def stop_receive(pid) do
    GenStateMachine.cast(pid, :stop)
  end

  @impl true
  def handle_event(:cast, :start, :stopping, data) do
    # stopping -> receiving
    # Logger.info("start, state change to receiving")
    {:next_state, :receiving, data, [{:next_event, :internal, :receive_message}]}
  end

  def handle_event(
        :internal,
        :receive_message,
        :receiving,
        %{queue: queue, receive_opts: opts} = data
      ) do
    # receiving -> resting
    case MNS.receive_message(queue, opts) do
      {:ok, %{body: %{"Messages" => messages}}} ->
        # Logger.info("receive message get:" <> inspect(messages))
        Process.send(data.parent, {:receive, messages}, [:noconnect])
        {:noreply, data, {:continue, :receive_message}}
        {:next_state, :resting, data, [{:state_timeout, 100, :go_receiving}]}

      {:error, %{body: %{"Error" => %{"Code" => "MessageNotExist"}}}} ->
        {:next_state, :resting, data,
         [{:state_timeout, data.retry_receive_message_interval, :go_receiving}]}

      error ->
        Logger.warn("receive message error:" <> inspect(error))

        {:next_state, :resting, data,
         [{:state_timeout, data.retry_receive_message_interval, :go_receiving}]}
    end
  end

  def handle_event(:cast, :start, _, _data) do
    # Logger.info("start, keep_state_and_data")
    :keep_state_and_data
  end

  def handle_event(:cast, :stop, :stopping, _data) do
    # Logger.info("stop, keep_state_and_data")
    :keep_state_and_data
  end

  def handle_event(:cast, :stop, _, data) do
    # * -> stopping
    # Logger.info("stop, state change to stopping")
    {:next_state, :stopping, data}
  end

  def handle_event(:state_timeout, :go_receiving, :resting, data) do
    # resting -> receiving
    # Logger.info("go_receiving, state change to receiving")
    {:next_state, :receiving, data, [{:next_event, :internal, :receive_message}]}
  end
end
