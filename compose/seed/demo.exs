defmodule XiangjianDemoSeed do
  alias Rice.Accounts
  alias Rice.Accounts.User
  alias Rice.Community.Node
  alias Rice.Grains
  alias Rice.PDS
  alias Rice.Repo
  alias Rice.Tasks

  @alice "alice.uat.test"
  @bob "bob.uat.test"
  @extra_accounts [
    %{
      handle: "chenxi.uat.test",
      nickname: "陈溪",
      email: "chenxi@uat.invalid",
      grains: 300,
      description: "记录乡村建筑与公共空间。"
    },
    %{
      handle: "linlan.uat.test",
      nickname: "林岚",
      email: "linlan@uat.invalid",
      grains: 260,
      description: "关注社区教育和儿童活动。"
    },
    %{
      handle: "zhouye.uat.test",
      nickname: "周野",
      email: "zhouye@uat.invalid",
      grains: 220,
      description: "参与在地农业与生态调查。"
    }
  ]

  def run do
    alice =
      case Repo.get_by(User, handle: @alice) do
        nil -> seed()
        alice ->
          IO.puts("demo data already exists")
          alice
      end

    seed_demo_node(alice)
    seed_extra_accounts()
  end

  defp seed do
    password = System.fetch_env!("MOCK_ACCOUNT_PASSWORD")
    alice = register(@alice, "阿禾", "alice@uat.invalid", password)
    bob = register(@bob, "木川", "bob@uat.invalid", password)

    Grains.grant(alice, 500, memo: "Demo 初始稻米") |> ok!("grant Alice")
    Grains.grant(bob, 200, memo: "Demo 初始稻米") |> ok!("grant Bob")

    node = seed_demo_node(alice)

    Tasks.create_task(alice, %{
      node_id: node.id,
      title: "[Demo] 记录村口古树故事",
      description: "访谈一位村民并整理一段口述记录。",
      reward_amount: 80,
      application_deadline: DateTime.add(DateTime.utc_now(), 30, :day)
    })
    |> ok!("create task")

    alice_session = PDS.create_session(@alice, password) |> ok!("login Alice")
    bob_session = PDS.create_session(@bob, password) |> ok!("login Bob")

    PDS.put_profile(alice_session["accessJwt"], alice_session["did"], %{
      "displayName" => "阿禾",
      "description" => "关注乡村记忆和社区共创。"
    })
    |> ok!("write Alice profile")

    PDS.put_profile(bob_session["accessJwt"], bob_session["did"], %{
      "displayName" => "木川",
      "description" => "做地图，也做一点农田水利调查。"
    })
    |> ok!("write Bob profile")

    create_post(
      alice_session,
      "demo-alice-welcome",
      "乡建 Demo 广场开张，欢迎记录村庄里的小发现。 #乡建",
      "post"
    )

    create_post(
      bob_session,
      "demo-bob-activity",
      "周六一起整理老粮站的口述资料。 #社区共创",
      "activity"
    )

    IO.puts("demo data is ready")
    alice
  end

  defp seed_demo_node(alice) do
    case Repo.get_by(Node, legacy_id: "demo-wamo-social") do
      nil ->
        %Node{}
        |> Node.changeset(%{
          legacy_id: "demo-wamo-social",
          name: "青禾测试社区",
          description: "demo.wamo.social 内测社区，仅使用测试账号和测试稻米。",
          user_id: alice.id
        })
        |> Repo.insert!()

      %Node{user_id: user_id} = node when user_id == alice.id ->
        node

      _node ->
        raise "demo node already belongs to another administrator"
    end
  end

  defp seed_extra_accounts do
    password = System.fetch_env!("MOCK_ACCOUNT_PASSWORD")

    Enum.each(@extra_accounts, fn account ->
      # ponytail: successful-run idempotency is enough for disposable demo data;
      # reset the volumes after a partial account seed.
      unless Repo.get_by(User, handle: account.handle) do
        user = register(account.handle, account.nickname, account.email, password)
        Grains.grant(user, account.grains, memo: "Demo 初始稻米")
        |> ok!("grant #{account.handle}")

        session = PDS.create_session(account.handle, password) |> ok!("login #{account.handle}")

        PDS.put_profile(session["accessJwt"], session["did"], %{
          "displayName" => account.nickname,
          "description" => account.description
        })
        |> ok!("write #{account.handle} profile")
      end
    end)

    IO.puts("additional demo accounts are ready")
  end

  defp register(handle, nickname, email, password) do
    Accounts.register(%{
      handle: handle,
      nickname: nickname,
      email: email,
      password: password
    })
    |> ok!("create #{handle}")
    |> Map.fetch!(:user)
  end

  defp create_post(session, rkey, text, category) do
    response =
      Req.post(
        System.fetch_env!("PDS_BASE_URL") <> "/xrpc/com.atproto.repo.createRecord",
        auth: {:bearer, session["accessJwt"]},
        json: %{
          "repo" => session["did"],
          "collection" => "app.bsky.feed.post",
          "rkey" => rkey,
          "record" => %{
            "$type" => "app.bsky.feed.post",
            "text" => text,
            "langs" => ["zh"],
            "xjdaoCategory" => category,
            "createdAt" => DateTime.utc_now() |> DateTime.to_iso8601()
          }
        },
        receive_timeout: 20_000
      )

    case response do
      {:ok, %{status: status}} when status in 200..299 -> :ok
      other -> raise "create post failed: #{inspect(other)}"
    end
  end

  defp ok!({:ok, value}, _label), do: value
  defp ok!({:error, reason}, label), do: raise("#{label} failed: #{inspect(reason)}")
end
