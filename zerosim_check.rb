# -*- coding: utf-8 -*-
#
# Zero Sim 容量チェックスクリプト
# Ruby 2.2.4で作成

require 'mechanize'
require 'nokogiri'
require 'pp'
require 'sqlite3'
require 'yaml'
require 'mail'
require 'active_support/all'

# 会員ログインページ
url = 'https://www.so-net.ne.jp/retail/u/userMenu/'

config=YAML.load_file("auth_user.yml")
user = config['user']
passwd = config['password']
mail = config['mail']
mail_from = config['mail_from']

# データベースとテーブル作成
SQLite3::Database.new("zero.db") do |db|
  db.execute(<<-EOL
    CREATE TABLE IF NOT EXISTS use_data (
      use_year number,
      use_month number,
      use_data number,
      PRIMARY KEY (use_year,use_month)
    );
  EOL
  )
end

# 会員ページへログイン
today_data = 0
before_yesterday_data = 0
agent = Mechanize.new
agent.user_agent_alias = 'Windows IE 7'
agent.get(url) do | page |
  mypage = page.form_with(name:'Login') do | form |
      form.IDToken1 = user
      form.IDToken2 = passwd
  end.submit

  # 容量を取得
  res = mypage.form_with(name:'userUsageActionForm').submit
  html = Nokogiri::HTML.parse(res.body)
  today_data = html.xpath('//dl[@class="useConditionDisplay"]/dt[contains(text(),"今月のデータ使用量(速報値)")]/following-sibling::dd').text.gsub(/(\s)/,"").gsub(/MB$/,"").to_i
  before_yesterday_data = html.xpath('//dl[@class="useConditionDisplay"]/dt[contains(text(),"一昨日のデータ使用量")]/following-sibling::dd').text.gsub(/(\s)/,"").gsub(/MB$/,"").to_i

end
pp before_yesterday_data
pp today_data
# データベースに格納
SQLite3::Database.new("zero.db") do |db|
  db.prepare('REPLACE INTO use_data (use_year,use_month,use_data) VALUES (?,?,?)') do |stmt|
    # 今月の容量
    today = Date.today
    stmt.execute(today.year,today.month,today_data)
    # 会員サイトでは、先月の容量が確認できないので、
    # 一昨日が先月だったら、先月の容量が確定しているものとして更新する。
    day_before_yesterday = today -3.day
    if today.month != day_before_yesterday.month
      stmt.execute(day_before_yesterday.year,day_before_yesterday.month,before_yesterday_data)
    end
  end
  # ZeroSimは３か月未利用だと自動解約されるので、直近２か月未利用だったら警告を出す。
  limit_date = Date.today.prev_month
  db.prepare('SELECT SUM(use_data) as todal_data FROM use_data WHERE use_year * 100 + use_month >= ?') do |stmt|
    stmt.execute(limit_date.year * 100 + limit_date.month).each do | ret |
      if ret[0] == 0
        mail = Mail.new do
          from mail_from
          to mail
          subject 'Zero Sim 解約警告'
          body '２か月間使用容量が0MBです。３か月未利用だと自動解約されます。'
        end
        mail.charset = 'utf-8'
        mail.delivery_method :sendmail
        mail.deliver
      end
    end
  end
end
# 容量上限チェック
if today_data >= 400
  mail = Mail.new do
    from mail_from
    to mail
    subject 'Zero Sim 容量警告'
    body '今月の使用容量が400MBを超えています。'
  end
  mail.delivery_method :sendmail
  mail.deliver
end

exit 0  

