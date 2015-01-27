#!/bin/ruby
# -*- coding: utf-8 -*-
# The program takes a folder of movie and user data and then
# parses it into accessible categories along the lines of
# ratings and similarities amongst users as well as popularity
# against fellow movies.
#
# Author::    Jonathan Schmeling  (mailto:jaft@brandeis.edu)
# Copyright:: Copyright (c) 2015
# License::   Distributes under the same terms as Ruby
require "set"

# Loads and parses the movie data
class MovieData
  def initialize(folder, idk = :idk)
    if(idk == :idk)
      @base = load_data("#{folder}/u.data")
    else
      @base = load_data("#{folder}/#{idk}.base")
      @test = load_test_data("#{folder}/#{idk}.test")
    end
  end

  # Returns all data for base file
  def get_data()
    @base
  end

  # Returns data array for test file
  def get_test_data()
    @test
  end

  # Loads test data. Test data is a simple array of tuples [u, m, r].
  # Since all I'm really doing is iterating through each line of the test
  # file for some amount, all I need is each line as a bundle
  def load_test_data(file)
    ret_data = []

    IO.foreach(file) do |l|
      ui, mi, r, ts = l.split
      user_id, movie_id, rating, timestamp = ui.to_i, mi.to_i, r.to_i, ts.to_i

      ret_data.push([user_id, movie_id, rating])
    end

    ret_data
  end

  # this will read in the data from the original ml-100k files
  # and stores them in whichever way it needs to be stored
  def load_data(file)
    ret_data = {
                users: Set.new,
                user_id: Hash.new,
                movies: Set.new,
                movie_id: Hash.new
               }

    IO.foreach(file) do |l|
      ui, mi, r, ts = l.split
      user_id, movie_id, rating, timestamp = ui.to_i, mi.to_i, r.to_i, ts.to_i

      # mov_and_rat = movies_and_ratings
      # use_and_rat = users_and_ratings
      # most_sim = hash of users most similar to user_id sorted by
      #            a movie *all* of them have rated
      # similarity = hash of similarities sorted by user that user_id is sim. to
      ret_data[:users].add(user_id)
      unless(ret_data[:user_id][user_id])
        ret_data[:user_id][user_id] = {
                                       mov_and_rat: { movie_id => rating },
                                       titles: [movie_id],
                                       most_sim: Hash.new,
                                       similarity: Hash.new
                                      }
      else
        ret_data[:user_id][user_id][:mov_and_rat][movie_id] = rating
        ret_data[:user_id][user_id][:titles].push(movie_id)
      end

      ret_data[:movies].add(movie_id)
      unless(ret_data[:movie_id][movie_id])
        ret_data[:movie_id][movie_id] = {
                                         use_and_rat: { user_id => rating },
                                         ratings: [rating],
                                         users: [user_id]
                                        }
      else
        ret_data[:movie_id][movie_id][:use_and_rat][user_id] = rating
        ret_data[:movie_id][movie_id][:ratings].push(rating)
        ret_data[:movie_id][movie_id][:users].push(user_id)
      end
    end

    ret_data
  end

  # Predicts user rating by collecting the most similar users to user u
  # and then filtering out all users who have not watched the movie we're
  # predicting. If this filters out all users, decrease the degree of similarity
  # by 0.1 and do it again.
  def predict(u, m)
    u, m = u.to_i, m.to_i
    # Finds all possible similar users that've reviewed movie m unless none exist
    def shared_sim_users(us, mo, n = 5)
      return [] if(n < 1) # If we've run so many times that we're going below 1.0
                          # (an impossible similarity), there is no similar users
      # Select all similar users who have seen the movie we're predicting
      ta = self.most_similar(us, n).select do |user|
             @base[:user_id][user][:titles].include?(mo)
           end
      # If we wind up empty after that filtering, run again but w/ 0.1 less sim.
      ta = shared_sim_users(us, mo, (n - 0.1)) if(ta == [])
      return ta
    end

    # If we've saved a list of most similar users based on movie m for user
    # u already, use that; otherwise, run the recursive local method above
    if(@base[:user_id][u][:most_sim][m])
      ss = @base[:user_id][u][:most_sim][m]
    else
      ss = shared_sim_users(u, m)
    end
    # If there are no similar users that have seen this movie (therefore, likely
    # no one but user u has reviewed this movie), likely not popular so just
    # guess 1
    if(ss == [])
      return 1.0
    else
      # Given our algorithm literally just finds the most *possible* similar
      # users, all of those users like share the same similar users
      # Cache every user here as the most similar user of every other user here
      @base[:user_id][u][:most_sim][m] = ss
      ss.each do |e|
        ts = ss.dup
        ts[ts.index(e)] = u
        @base[:user_id][e][:most_sim][m] = ts
      end
      # Take the average of the ratings all of similar users gave this movie
      # and that's our prediction
      return ss.inject(0){ |sum, user| sum+@base[:user_id][user][:mov_and_rat][m] }/(ss.length*1.0)
    end
  end

  # Runs the predict() method on the first k ratings in the test set and returns
  # a MovieTest object containing the results.
  #
  # * The parameter k is optional and if omitted, all of the tests will be run.
  def run_test(k = -1)
    array = []
    cum_diff = 0
    rms_tool = 0
    k = @test.length if(k < 0)

    @test.take(k).each do |user, movie, rating|
      pred = self.predict(user, movie)
      array.push([user, movie, rating, pred])
      cum_diff += (pred - rating).abs
      rms_tool += pred**2
    end

    ave_cum_diff = cum_diff / k
    stand_dev = array.inject(0) { |sum, u| sum + ((u[3] - ave_cum_diff)**2) } / k
    rms = Math.sqrt(rms_tool / k)

    return MovieTest.new(ave_cum_diff, stand_dev, rms, array)
  end

  # this will return a number that indicates the popularity (higher
  # numbers are more popular). You should be prepared to explain the
  # reasoning behind your definition of popularity
  #
  # The algorithm comes from here: http://stackoverflow.com/a/1411455.
  # The first definition given by Dictionary.com for popular is
  # "regarded with favor, approval, or affection by people in general".
  # As such, I wanted the average score to indicate favor while bearing
  # in mind how many had reviewed the film in order to indicate the "people
  # in general" bit. As such, films with a larger degree of people who reviewed
  # them get a slight boost added in comparison to films with a low degree.
  def popularity(movie_id)
    movie_id = movie_id.to_i
    unless(@base[:movie_id][movie_id][:popularity])
      factor = 1.1
      tot_ratings = @base[:movie_id][movie_id][:ratings].length
      ave_rating = @base[:movie_id][movie_id][:ratings].inject(:+) / tot_ratings
      pop = ((1 - (1/(factor ** tot_ratings))) * ave_rating) +
            (3/(factor ** tot_ratings))

      @base[:movie_id][movie_id][:popularity] = pop
    end

    @base[:movie_id][movie_id][:popularity]
  end

  # this will generate a list of all movie_id’s ordered by decreasing
  # popularity
  def popularity_list
    ta = [] # temporary array
    @base[:movie_id].each do |k, v|
      self.popularity(k) unless(@base[:movie_id][k][:popularity])
      ta.push([k, @base[:movie_id][k][:popularity]])
    end

    ta.sort { |a, b| b[1] <=> a[1] }.map { |r| r[0] }
  end

  # this will generate a number which indicates the similarity in
  # movie preference between user1 and user2 (where higher numbers
  # indicate greater similarity)
  #
  # Calculates by taking the difference between each movie both users
  # have watched and adding each subsequent calculated difference.
  # That final sum is then divided by the number of films both users
  # have watched (thereby excluding any which one of them – but not the
  # other – may've seen).
  def similarity(user1, user2)
    user1, user2 = user1.to_i, user2.to_i
    unless(@base[:user_id][user1][:similarity][user2])
      userA, userB = nil
      if(@base[:user_id][user1][:titles].length < @base[:user_id][user2][:titles].length)
        userA = @base[:user_id][user1][:mov_and_rat]
        userB = @base[:user_id][user2][:mov_and_rat]
      else
        userA = @base[:user_id][user2][:mov_and_rat]
        userB = @base[:user_id][user1][:mov_and_rat]
      end

      sim = 0
      count = 0
      userA.each do |k, v|
        (sim += 5 + (v - userB[k]).abs * -1.0; count += 1) if(userB[k])
      end

      simil = sim / if(count > 0) then count else 1 end
      @base[:user_id][user1][:similarity][user2] = simil
      @base[:user_id][user2][:similarity][user1] = simil
      return simil
    else
      return @base[:user_id][user1][:similarity][user2]
    end
  end

  # this return a list of users whose tastes are most similar to the
  # tastes of user u
  #
  # Most similar is kind of vague so I just took anyone to have a difference
  # no greater than 0.2 from entirely similar (5.0). This allows for the event
  # that no one has the exact same tastes as the user, ze can at least get a
  # few people who are close in taste to zir.
  def most_similar(u, s)
    u = u.to_i
    @base[:users].select do |user|
      self.similarity(user, u) >= s unless(user == u)
    end
  end
end

# Stores test info.
class MovieTest
  def initialize(ave_pred_error, stand_deviation, root_mean_sqr, array)
    @ave_pred_error = ave_pred_error
    @stand_deviation = stand_deviation
    @root_mean_sqr = root_mean_sqr
    @array = array
  end

  def mean()
    @ave_pred_error
  end

  def stddev()
    @stand_deviation
  end

  def rms()
    @root_mean_sqr
  end

  def to_a()
    @array
  end
end
    

# a = MovieData.new
# a.load_data()

# btime = Time.now
# puts "First 10 of popularity list:\n#{a.popularity_list()[0..9]}\n\n"

# puts "Last 10 of popularity list:\n#{a.popularity_list()[-10..-1]}\n\n"

# puts "Most similar to 1 (since the list is less than 10, I just do this once):"
# puts "#{a.most_similar(1)}"
# etime = Time.now

# puts "Total Time = #{((etime - btime) * 1000)}"


# btime = Time.now
a = MovieData.new("ml-100k", :u1)
b = a.run_test()
# etime = Time.now
puts "Set information…"
puts "average prediction error: #{b.mean}"
puts "standard deviation: #{b.stddev}"
puts "root mean square: #{b.rms}"
# puts "Total Time = #{((etime - btime) / 60)}"
