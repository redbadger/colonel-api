source 'https://rubygems.org'

ruby '2.2.2'

gem 'sinatra'
gem 'thin'
gem 'colonel',
    '~> 0.6.1',
    git: 'https://github.com/bskyb/colonel',
    tag: 'v0.6.1'
gem 'rugged',
    git: 'https://github.com/redbadger/rugged',
    branch: 'backends',
    submodules: true
gem 'rugged-redis',
    git: 'https://github.com/redbadger/rugged-redis',
    tag: 'v0.1.1',
    submodules: true

group :test, :development do
  gem 'pry'
  gem 'rubocop'
end

group :test do
  gem 'rspec'
  gem 'rack-test'
  gem 'redis'
end
