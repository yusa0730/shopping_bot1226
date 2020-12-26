# ① LINEからテキストメッセージを受け取る。

# ② 入力値で楽天APIを用いて商品検索を行い、先頭の商品のジャンルを取得する。

# ③ 再び楽天APIを使い、取得したジャンル内で、入力値でランキングを取得する。（※1）

# ④ 取得したランキングの１〜３位までの「商品概要」・「画像URL」・「価格」・「商品のリンク」を使い、Flex Message（※2）で決められた形式にする。

# ⑤ ④をリプライとして返す。

# ※1 楽天APIの仕様上、全てのジャンルでのランキングは取得できないため、このような実装としています。

# ※2 LINEの返信で、複数の要素を組み合わせてレイアウトを自由にカスタマイズできるメッセージのことです。詳細（LINEの公式ドキュメント）はこちら。

class LinebotsController < ApplicationController
  require 'line/bot'
  # このメソッドはCSRF対策しているから大丈夫、しなくても大丈夫、だから外部からリクエストできるようにしたい。
  # 特定のメソッドだけCSRFの対策をしたくない場合は、そのメソッドのあるコントローラでこんな風に定義します。
  protect_from_forgery except: [:callback]

  def callback
    body = request.body.read
    # X-Line-Signatureリクエストヘッダーに含まれる署名を検証して、リクエストがLINEプラットフォームから送信されたことを確認する必要があります
    signature = request.env['HTTP_X_LINE_SIGNATURE']
    unless client.validate_signature(body, signature)
      return head :bad_request
    end
    events = client.parse_events_from(body)
    events.each do |event|
      case event
      when Line::Bot::Event::Message
        case event.type
        when Line::Bot::Event::MessageType::Text
          # 入力した文字をinputに格納
          input = event.message['text']
          # search_and_create_messageメソッド内で、楽天APIを用いた商品検索、メッセージの作成を行う
          message = search_and_create_message(input)
          client.reply_message(event['replyToken'], message)
        end
      end
    end
    head :ok
  end

  private

  def client
    @client ||= Line::Bot::Client.new do |config|
      config.channel_secret = ENV['LINE_BOT_CHANNEL_SECRET']
      config.channel_token = ENV['LINE_BOT_CHANNEL_TOKEN']
    end
  end

  def search_and_create_message(input)
    RakutenWebService.configure do |c|
      c.application_id = ENV[]
      c.affiliate_id = ENV[]
    end
    # 楽天の商品検索APIで画像がある商品の中で、入力値で検索して上から3件を取得する
    # 商品検索+ランキングでの取得はできないため標準の並び順で上から3件取得する
    res = RakutenWebService::Ichiba::Item.search(keyword: input, hits: 3, imageFlag: 1)
    items = []
    # 取得したデータを使いやすいように配列に格納し直す
    items = res.map{|item| item}
    make_reply_content(items)
  end

  def make_reply_content(items)
    {
      "type": 'flex',
      "altText": 'This is a Flex Message',
      "contents":
      {
        "type": 'carousel',
        "contents": [
          make_part(items[0]),
          make_part(items[1]),
          make_part(items[2])
        ]
      }
    }
  end

  def make_part(item)
    title = item['itemName']
    price = item['itemPrice'].to_s + '円'
    url = item['itemUrl']
    image = item['mediumImageUrls'].first
    {
      "type": "bubble",
      "hero": {
        "type": "image",
        "size": "full",
        "aspectRatio": "20:13",
        "aspectMode": "cover",
        "url": image
      },
      "body":
      {
        "type": "box",
        "layout": "vertical",
        "spacing": "sm",
        "contents": [
          {
            "type": "text",
            "text": title,
            "wrap": true,
            "weight": "bold",
            "size": "lg"
          },
          {
            "type": "box",
            "layout": "baseline",
            "contents": [
              {
                "type": "text",
                "text": price,
                "wrap": true,
                "weight": "bold",
                "flex": 0
              }
            ]
          }
        ]
      },
      "footer":{
        "type": "box",
        "layout": "vertical",
        "spacing": "sm",
        "contents": [
          {
            "type": "button",
            "style": "primary",
            "action":{
              "type": "uri",
              "label": "楽天市場商品ページへ",
              "uri": url
            }
          }
        ]
      }
    }  
  end
end
