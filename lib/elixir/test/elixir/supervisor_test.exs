Code.require_file "test_helper.exs", __DIR__

defmodule SupervisorTest do
  use ExUnit.Case, async: true

  defmodule Stack do
    use GenServer

    def start_link(state, opts) do
      GenServer.start_link(__MODULE__, state, opts)
    end

    def handle_call(:pop, _from, [h | t]) do
      {:reply, h, t}
    end

    def handle_call(:stop, _from, stack) do
      # There is a race condition between genserver terminations.
      # So we will explicitly unregister it here.
      try do
        self() |> Process.info(:registered_name) |> elem(1) |> Process.unregister
      rescue
        _ -> :ok
      end
      {:stop, :normal, :ok, stack}
    end

    def handle_cast({:push, h}, t) do
      {:noreply, [h | t]}
    end
  end

  defmodule Stack.Sup do
    use Supervisor

    def init({arg, opts}) do
      children = [worker(Stack, [arg, opts])]
      supervise(children, strategy: :one_for_one)
    end
  end

  import Supervisor.Spec

  test "start_link/2 with via" do
    Supervisor.start_link([], strategy: :one_for_one, name: {:via, :global, :via_sup})
    assert Supervisor.which_children({:via, :global, :via_sup}) == []
  end

  test "start_link/3 with global" do
    Supervisor.start_link([], strategy: :one_for_one, name: {:global, :global_sup})
    assert Supervisor.which_children({:global, :global_sup}) == []
  end

  test "start_link/3 with local" do
    Supervisor.start_link([], strategy: :one_for_one, name: :my_sup)
    assert Supervisor.which_children(:my_sup) == []
  end

  test "start_link/2" do
    children = [worker(Stack, [[:hello], [name: :dyn_stack]])]
    {:ok, pid} = Supervisor.start_link(children, strategy: :one_for_one)

    wait_until_registered(:dyn_stack)
    assert GenServer.call(:dyn_stack, :pop) == :hello
    assert GenServer.call(:dyn_stack, :stop) == :ok

    wait_until_registered(:dyn_stack)
    assert GenServer.call(:dyn_stack, :pop) == :hello
    Supervisor.stop(pid)

    assert_raise ArgumentError, ~r"expected :name option to be one of:", fn ->
      Supervisor.start_link(children, name: "my_gen_server_name", strategy: :one_for_one)
    end

    assert_raise ArgumentError, ~r"expected :name option to be one of:", fn ->
      Supervisor.start_link(children, name: {:invalid_tuple, "my_gen_server_name"}, strategy: :one_for_one)
    end

    assert_raise ArgumentError, ~r"expected :name option to be one of:", fn ->
      Supervisor.start_link(children, name: {:via, "Via", "my_gen_server_name"}, strategy: :one_for_one)
    end
  end

  test "start_link/3" do
    {:ok, pid} = Supervisor.start_link(Stack.Sup, {[:hello], [name: :stat_stack]})
    wait_until_registered(:stat_stack)
    assert GenServer.call(:stat_stack, :pop) == :hello
    Supervisor.stop(pid)
  end

  test "*_child functions" do
    {:ok, pid} = Supervisor.start_link([], strategy: :one_for_one)

    assert Supervisor.which_children(pid) == []
    assert Supervisor.count_children(pid) ==
           %{specs: 0, active: 0, supervisors: 0, workers: 0}

    {:ok, stack} = Supervisor.start_child(pid, worker(Stack, [[:hello], []]))
    assert GenServer.call(stack, :pop) == :hello

    assert Supervisor.which_children(pid) ==
           [{SupervisorTest.Stack, stack, :worker, [SupervisorTest.Stack]}]
    assert Supervisor.count_children(pid) ==
           %{specs: 1, active: 1, supervisors: 0, workers: 1}

    assert Supervisor.delete_child(pid, Stack) == {:error, :running}
    assert Supervisor.terminate_child(pid, Stack) == :ok

    {:ok, stack} = Supervisor.restart_child(pid, Stack)
    assert GenServer.call(stack, :pop) == :hello

    assert Supervisor.terminate_child(pid, Stack) == :ok
    assert Supervisor.delete_child(pid, Stack) == :ok
    Supervisor.stop(pid)
  end

  defp wait_until_registered(name) do
    unless Process.whereis(name) do
      wait_until_registered(name)
    end
  end
end
