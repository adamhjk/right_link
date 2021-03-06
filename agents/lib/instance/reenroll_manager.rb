#
# Copyright (c) 2009 RightScale Inc
#
# Permission is hereby granted, free of charge, to any person obtaining
# a copy of this software and associated documentation files (the
# "Software"), to deal in the Software without restriction, including
# without limitation the rights to use, copy, modify, merge, publish,
# distribute, sublicense, and/or sell copies of the Software, and to
# permit persons to whom the Software is furnished to do so, subject to
# the following conditions:
#
# The above copyright notice and this permission notice shall be
# included in all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
# NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
# LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
# OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
# WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

module RightScale

  # Tracks reenroll votes and trigger reenroll as necessary
  class ReenrollManager

    # Number of votes required to trigger re-enroll
    REENROLL_THRESHOLD = 3

    # Delay in seconds until votes count is reset if no more votes occur
    # This value should be more than two hours as this is the period at which
    # votes will get generated in offline mode
    RESET_DELAY = 7200 # 2 hours

    # Vote for re-enrolling, if threshold is reached re-enroll
    # If no vote occurs in the next two hours, then reset counter
    #
    # === Return
    # true:: Always return true
    def self.vote
      @total_votes ||= 0
      @reenrolling ||= false
      @total_votes += 1
      @reset_timer.cancel if @reset_timer
      @reset_timer = EM::Timer.new(RESET_DELAY) { reset_votes }
      if @total_votes >= REENROLL_THRESHOLD && !@reenrolling
        RightLinkLog.info('[re-enroll] Re-enroll threshold reached, shutting down and re-enrolling')
        @reenrolling = true
        system('rs_reenroll')
      end
      true
    end

    # Reset votes count
    #
    # === Return
    # true:: Always return true
    def self.reset_votes
      @total_votes = 0
      @reset_timer = nil
      true
    end

  end
end
