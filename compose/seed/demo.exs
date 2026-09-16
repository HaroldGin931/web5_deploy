defmodule XiangjianDemoSeed do
  alias Rice.Accounts
  alias Rice.Accounts.User
  alias Rice.Community.Node
  alias Rice.Events
  alias Rice.Grains
  alias Rice.PDS
  alias Rice.Repo
  alias Rice.Tasks

  @alice "alice.uat.test"
  @bob "bob.uat.test"
  @linlan "linlan.uat.test"
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
        nil ->
          seed()

        alice ->
          IO.puts("demo data already exists")
          alice
      end

    demo_node = seed_demo_node(alice)
    seed_extra_accounts()

    linlan = Repo.get_by!(User, handle: @linlan)
    learning_node = seed_learning_node(linlan)

    seed_events(alice, demo_node, linlan, learning_node)
    seed_demo_posts()
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

  defp seed_learning_node(linlan) do
    case Repo.get_by(Node, legacy_id: "demo-linxia-learning") do
      nil ->
        %Node{}
        |> Node.changeset(%{
          legacy_id: "demo-linxia-learning",
          name: "林下共学社区",
          description: "面向社区教育、儿童自然观察与公共空间共建的内测社区。",
          position: 10,
          user_id: linlan.id
        })
        |> Repo.insert!()

      %Node{user_id: user_id} = node when user_id == linlan.id ->
        node

      _node ->
        raise "learning node already belongs to another administrator"
    end
  end

  defp seed_events(alice, demo_node, linlan, learning_node) do
    now = DateTime.utc_now()
    day = 86_400

    [
      {alice, demo_node, "demo-qinghe-tree-walk-v1", "[Demo] 古树故事采集散步", "一起走访村口古树，记录树木、地名和村民记忆。",
       "青禾村口集合点", 5, 7, 2, 12},
      {alice, demo_node, "demo-qinghe-oral-history-v1", "[Demo] 老粮站口述史整理会",
       "整理老粮站访谈素材，共同制作社区口述史索引。", "青禾社区公共客厅", 8, 10, 3, 16},
      {linlan, learning_node, "demo-linxia-nature-class-v1", "[Demo] 儿童自然观察工作坊",
       "带孩子观察常见植物和昆虫，并完成一页自然笔记。", "林下共学社区自然角", 12, 14, 2, 10},
      {linlan, learning_node, "demo-linxia-picture-book-v1", "[Demo] 社区绘本共读与交换日",
       "共读乡土主题绘本，并交换家中闲置的儿童读物。", "林下共学社区阅读室", 18, 21, 3, 20}
    ]
    |> Enum.each(fn {owner, node, request_id, title, description, location, deadline_days,
                     start_days, duration_hours, capacity} ->
      starts_at = DateTime.add(now, start_days * day)

      Events.create_event(owner, %{
        node_id: node.id,
        status: "open",
        client_request_id: request_id,
        title: title,
        description: description,
        location: location,
        fee_amount: 0,
        capacity: capacity,
        application_deadline: DateTime.add(now, deadline_days * day),
        starts_at: starts_at,
        ends_at: DateTime.add(starts_at, duration_hours * 3_600)
      })
      |> ok!("create #{request_id}")
    end)

    IO.puts("demo communities and events are ready")
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

  defp seed_demo_posts do
    password = System.fetch_env!("MOCK_ACCOUNT_PASSWORD")

    [
      {@alice, "demo-v2-alice-community-note", "青禾测试社区的公共议事角已经整理好，欢迎一起记录村庄里的问题和办法。 #社区共建"},
      {@bob, "demo-v2-bob-water-note", "今天沿着灌溉水渠走了一圈，标出了三处需要清淤的位置。下次带上卷尺再补一版地图。 #田野记录"},
      {"chenxi.uat.test", "demo-v2-chenxi-building-note",
       "老礼堂的木屋架保存得比想象中完整，我把梁柱节点和窗格样式做成了一份建筑档案。 #乡村建筑"},
      {@linlan, "demo-v2-linlan-reading-note", "林下共学社区准备办一次儿童共读和绘本交换，家里有闲置绘本的朋友可以带来。 #社区教育"},
      {"zhouye.uat.test", "demo-v2-zhouye-field-note", "试验田边发现了几种常见授粉昆虫，这周会继续记录出现时间和天气变化。 #生态调查"}
    ]
    |> Enum.each(fn {handle, rkey, text} ->
      session = PDS.create_session(handle, password) |> ok!("login #{handle}")
      ensure_post(session, rkey, text)
    end)

    IO.puts("demo posts are ready")
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
    response = create_post_request(session, rkey, text, category)

    case response do
      {:ok, %{status: status}} when status in 200..299 -> :ok
      other -> raise "create post failed: #{inspect(other)}"
    end
  end

  defp ensure_post(session, rkey, text) do
    case get_post(session, rkey) do
      {:ok, record} ->
        verify_post!(record, text, rkey)

      :missing ->
        case create_post_request(session, rkey, text, "post") do
          {:ok, %{status: status}} when status in 200..299 ->
            :ok

          error ->
            case get_post(session, rkey) do
              {:ok, record} -> verify_post!(record, text, rkey)
              _other -> raise "create #{rkey} failed: #{inspect(error)}"
            end
        end

      {:error, error} ->
        raise "read #{rkey} failed: #{inspect(error)}"
    end
  end

  defp get_post(session, rkey) do
    url =
      System.fetch_env!("PDS_BASE_URL") <>
        "/xrpc/com.atproto.repo.getRecord?" <>
        URI.encode_query(%{
          "repo" => session["did"],
          "collection" => "app.bsky.feed.post",
          "rkey" => rkey
        })

    case Req.get(url, auth: {:bearer, session["accessJwt"]}, receive_timeout: 20_000) do
      {:ok, %{status: 200, body: %{"value" => record}}} -> {:ok, record}
      {:ok, %{status: 400, body: %{"error" => "RecordNotFound"}}} -> :missing
      error -> {:error, error}
    end
  end

  defp verify_post!(record, text, rkey) do
    if record["text"] == text and record["xjdaoCategory"] == "post" do
      :ok
    else
      raise "post #{rkey} already exists with different content"
    end
  end

  defp create_post_request(session, rkey, text, category) do
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
  end

  defp ok!({:ok, value}, _label), do: value
  defp ok!({:error, reason}, label), do: raise("#{label} failed: #{inspect(reason)}")
end
