require 'sinatra'
require 'colonel'
require 'rugged-redis'
require 'pry'

Colonel.config.elasticsearch_uri = 'elasticsearch:9200'

redis_backend = Rugged::Redis::Backend.new(host: 'redis', port: 6379)
Colonel.config.rugged_backend = redis_backend

class App < Sinatra::Base
  set :bind, '0.0.0.0'

  get '/' do
    doc = Colonel::Document.new({title: 'Hello Colonel', tags: ['Test', 'Content'], body: 'Some text.'})
    doc.content.title
  end

  run! if app_file == $0
end
