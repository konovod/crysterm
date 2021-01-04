require "event_handler"
require "term-screen"
require "tput"
require "log"

require "./macros"
require "./methods"
require "./widget/node"
require "./widget/*"

module Crysterm

  class Program
    ##include EventHandler
    include Methods
    include Macros
    include EventHandler

    @@global : self?
    @@total = 0
    @@instances = [] of self
    @@_bound = false

    class MyFD < IO::FileDescriptor
      include EventHandler
    end

    # wth?
    property x = 0
    property y = 0

    property input : MyFD
    property output : MyFD
    #@log : Bool
    @type = :program
    @index : Int32 = -1 # -1 so that assignments start from 0
    property use_buffer : Bool # useBuffer
    property resize_timeout : Int32

    getter terminfo : Unibilium::Terminfo?
    getter! tput : ::Tput

    @_tput_set_up = false

    @scroll_bottom : Int32

    getter is_alt = false

    getter _title : String?

    @cursor_hidden = false
    record CursorState, x : Int32, y : Int32, hidden : Bool

    @saved = {} of String => CursorState

    @ret = false

    @exiting = false

    getter _buf : String? = nil

    @x : Int32 = 0
    @y : Int32 = 0
    @saved_x : Int32 = 0
    @saved_y : Int32 = 0

    @dump = true

    def initialize(
      @input = MyFD.new(STDIN.fd),
      @output = MyFD.new(STDOUT.fd),
      @log = ::Log.for(self.class),
      @use_buffer = true,
      @force_unicode = false,
      @resize_timeout = 1, # TODO value
      terminfo = nil,
      @dump=true,
      @term = ENV["TERM"]? || "{% if flag?(:windows) %}windows-ansi{% else %}xterm{% end %}",
    )

      @x = 0
      @y = 0
      @saved_x = 0
      @saved_y = 0

      # TODO make these check @output, not STDOUT which is probably used.
      @cols = ::Term::Screen.cols || 1
      @rows = ::Term::Screen.rows || 1

      if @dump
        @input.on(DataEvent) { |d|
          Log.info { p d }
        }
        @output.on(DataEvent) { |d|
          Log.info { p d }
        }
      end

      @scroll_top = 0
      @scroll_bottom = @rows - 1

      # XXX This is just name of term. Run terminfo init,
      # then read this from there, not here.
      #@_terminal = terminal.downcase


      @_buf

      #bind
      # TODO _flush = this.flush.bind(this)

      @tput = setup_tput terminfo

      # TODO
      #listen
    end

    def bind
      @@global = self unless @@global

      unless @@instances.includes? self
        @@instances << self
        @index = @@total
        @@total += 1
      end

      return if @@_bound
      @@_bound = true

      # TODO the exit handler
    end

    def setup_tput(terminfo=nil)
      unless @_tput_set_up
        @_tput_set_up = true

        @terminfo = terminfo || Unibilium::Terminfo.from_env

        @tput = ::Tput.new(
          terminfo: @terminfo,
          # TODO these options
          #term: @term,
          #padding: @padding,
          #extended: @extended,
          #termcap: @termcap,
          use_buffer: @use_buffer,
          force_unicode: @force_unicode
        )

        # TODO tput stuff till end of function
      end
      @tput
    end

    def pause
      lsave_cursor "pause"
      normal_buffer if is_alt
      show_cursor

      #disable_mouse if mouse_enabled

      # TODO - zamijeniti sve pozive na IO.write sa _owrite,
      # a onda u toj funkciji dropati sve writeove ako je
      # u pause modu.
    end

    def resume
      if responds_to? :_resume
        _resume
      end
    end


    def title=(title)
      set_title title
    end

  end
end
