require 'rubygems'
require 'bundler'
require 'sinatra'
require 'erector'
require 'erector/widgets/page'
require 'pp'
require 'json'
require 'oauth'
require 'oauth/consumer'
require 'rest-client'

require './page'

class Rack::Request
  def site
    url = scheme + "://"
    url << host

    if scheme == "https" && port != 443 ||
        scheme == "http" && port != 80
      url << ":#{port}"
    end

    url
  end
end  

class Cohuman
  def self.credentials
    {
      :key => '29f16b7cef111cb8223614ca38080c8f6fdb2651',
      :secret => '82916a0c268d306ec8252367db6f9758d8f0625b'
    }
  end

  def self.consumer
    puts "---===---"
    puts credentials[:key]
    puts credentials[:secret]
    @consumer ||= OAuth::Consumer.new( credentials[:key], credentials[:secret], {
      :site => 'http://localhost:3000',
      :request_token_path => '/api/token/request',
      :authorize_path => '/api/authorize',
      :access_token_path => '/api/token/access'
    })
  end
  
  def self.api_url(path)
    path.gsub!(/^\//,'') # removes leading slash from path
    url = "http://localhost:3000/#{path}"
  end
  
end

def render_page(query = nil, result = nil)
  Page.new(:session => session, :request => request, :query => query, :result => result).to_html
end

enable :sessions

get "/" do
  render_page
end

get "/authorize" do
  if Cohuman.credentials
    request_token = Cohuman.consumer.get_request_token(
      :oauth_callback=>"#{request.site}/api/authorize"
    )
    session[:request_token] = request_token
    puts "______ Request Token"
    puts request_token.inspect
    puts "Redirecting to " + request_token.authorize_url
    redirect request_token.authorize_url
  else
    erector {
      h1 "Configuration error"
      ul {
        li {
          text "Please set the environment variables "
          code "COHUMAN_API_KEY"
          text " and " 
          code "COHUMAN_API_SECRET"
        }
        li {
          text " or create "
          code "config/cohuman.yml"
        }
      }
      p "For a Heroku app, do it like this:"
      pre <<-PRE
heroku config:add COHUMAN_API_KEY=asldjasldkjal
heroku config:add COHUMAN_API_SECRET=asdfasdfasdf
      PRE
    }
  end
end

get "/authorized" do
  request_token = session[:request_token]
  access_token = request_token.get_access_token
  session.delete :request_token  # comment this line out if you want to see the request token in the session table
  session[:access_token] = access_token
  redirect "/"
end

get "/logout" do
  if session[:access_token].nil?
    redirect "/"
    return
  end
  
  url = Cohuman.api_url("/logout")
  response = session[:access_token].post(url, {"Content-Type" => "application/json"})
  result = begin
    JSON.parse(response.body)
  rescue
    {
      :response => "#{response.code} #{response.message}",
      :headers => response.to_hash,
      :body => response.body
    }
  end
  
  session.delete(:access_token)
  session.delete(:request_token)

  render_page(url, result)
end

def get_and_render(path)
  url = Cohuman.api_url(path)
  response = session[:access_token].get(url, {"Content-Type" => "application/json"})
  render_page(url, JSON.parse(response.body))
end

# Do it through the Oauth gem
get "/tasks" do
  url = "http://localhost:3000/tasks"
  response = session[:access_token].get(url, {"Content-Type" => "application/json"})
  render_page(url, JSON.parse(response.body))
end

# Do it with rest-client
get "/users" do
  RestClient.add_before_execution_proc do |req, params|
    session[:access_token].sign! req
  end
  url = "http://localhost:3000/users?limit=5"
  response = RestClient.get(url, "Content-Type" => "application/json")
  puts response.inspect
  render_page(url, JSON.parse(response))
end

# Do a POST with the oauth gem
get "/projects" do
  url = 'http://localhost:3000/task/1643785/comment'
  response = session[:access_token].post(url, {:text => 'Hello Then', :format => 'json'}, {"Content-Type" => "application/json"})
  render_page(url, JSON.parse(response.body))
end


