require 'rubygems'
require 'treetop'

# make it utf-8 compatible for < 1.9 Ruby
if RUBY_VERSION < '1.9'
  require 'active_support'
  require 'oniguruma'

  include Oniguruma
  $KCODE = 'u'

  RegExp = ORegexp
  RegExp::IGNORECASE = ORegexp::OPTION_IGNORECASE

else
  RegExp = Regexp
  RegExp::IGNORECACASE = Regexp::IGNORECASE
end

FUZZY = RegExp.new('(?:(?<startcount>\d*)(?<startfuzz>~))?(?<text>[^~]+)(?:(?<endfuzz>~)?(?<endcount>\d*))$')

class WordMatch < Treetop::Runtime::SyntaxNode

  @@regex ||= {}
  @@regex_case ||= {}

  def eval(text, opt)
    query = opt[:regexp] ? RegExp.new(text_value) : RegExp.escape(text_value)
    qkey  = query + opt[:delim]

    if not @@regex[qkey]
      fuzzy = FUZZY.match(query)

      q = []
      if fuzzy[:startfuzz]
        q.push "."
        q.push fuzzy[:startcount].empty? ? "*" : "{#{fuzzy[:startcount]}}"
      end
      q.push fuzzy[:text]
      if fuzzy[4]
        q.push "."
        q.push fuzzy[:endcount].empty? ? "*" : "{#{fuzzy[:endcount]}}"
      end
      q = q.join

      regex = "(^|#{opt[:delim]})#{q}(#{opt[:delim]}|$)"

      @@regex[qkey] = RegExp.new(regex, :options => RegExp::IGNORECASE)
      @@regex_case[qkey] = RegExp.new(regex, nil)
    end

    if opt[:ignorecase]
      not @@regex[qkey].match(text).nil?
    else
      not @@regex_case[qkey].match(text).nil?
    end
  end

  def accept(&block)
    block.call(:value, text_value)
  end
end

Treetop.load File.dirname(__FILE__) + "/textquery_grammar"

class TextQueryError < RuntimeError
end

class TextQueryGrammarParser
  attr_reader :options

  def initialize options = {}
    @options = options
    super()
  end

  def update_options(options)
    @options = {:delim => ' '}.merge(options)
    @options[:delim] = "(#{[@options[:delim]].flatten.map { |opt| opt.is_a?(Regexp) ? opt : RegExp.escape(opt) }.join("|")})"
  end

  def _nt_attribute_delimiter
    attribute_delimiter = options.fetch(:attribute_delimiter, ':')
    if attribute_delimiter && attribute_delimiter.size > 0 && has_terminal?(attribute_delimiter, false, index)
      attribute_delimiter_size = attribute_delimiter.size
      r0 = instantiate_node(SyntaxNode,input, index...(index + attribute_delimiter_size))
      @index += attribute_delimiter_size
    else
      terminal_parse_failure(attribute_delimiter)
      r0 = nil
    end
    r0
  end
end

class TextQuery
  def initialize(query = '', options = {})
    @parser = TextQueryGrammarParser.new options
    @query  = nil

    @parser.update_options(options)
    parse(query) if not query.empty?
  end

  def parse(query)
    query = query.mb_chars if RUBY_VERSION < '1.9'
    @query = @parser.parse(query)
    if not @query
      raise TextQueryError, "Could not parse query string '#{query}': #{@parser.terminal_failures.inspect}"
    end
    self
  end

  def eval(input, options = {})
    @parser.update_options(options) if not options.empty?

    if @query
      @query.eval(input, @parser.options)
    else
      raise TextQueryError, 'no query specified'
    end
  end
  alias :match? :eval

  def accept(options = {}, &block)
    @parser.update_options(options) if not options.empty?

    if @query
      @query.accept(&block)
    else
      raise TextQueryError, 'no query specified'
    end
  end

  def terminal_failures
    @parser.terminal_failures
  end

end
