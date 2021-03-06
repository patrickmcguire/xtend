{ vows, assert, js, p, esprima, codegen } = require("./helpers")

m = (patternStr, jsCode, checker) ->
  rule = new js.Rule(patternStr, checker, esprima)
  tree = esprima.parse(jsCode)
  output = null
  js.traverse(tree, (node, parent, key) ->
    bindings = {}
    if rule.match(node, bindings, parent, key) && !output
      output = bindings
  )
  return output

r = (patternStr, jsCode, checker, visitor) ->
  writer = new js.Rewriter(esprima, codegen)
  writer.find(patternStr, checker).replaceWith(jsCode, visitor)
  return (code) ->
    tree = writer.convert(code)
    codegen.generate(tree)

vows.describe('js matching rules').addBatch
  'doing an exact match for assignment':
    topic: ->
      m('@a.@b = @c', 'blah.asdf = 3')
    'should match bindings': (bindings) ->
      assert.equal bindings.a.name, 'blah'
      assert.equal bindings.b.name, 'asdf'
      assert.equal bindings.c.value, 3

  'doing an exact unequal match':
    topic: ->
      m('@a.not_asdf = @c', 'blah.asdf = 3')
    'should not match bindings': (bindings) ->
      assert.equal bindings, null

  'doing an exact equal match with strings':
    topic: ->
      m('@a.something = "blah"', 'blah.something = "blah"')
    'should match bindings': (bindings) ->
      assert.equal bindings.a.name, 'blah'

  'match on object':
    topic: ->
      m('{@a: @b}', '{blah: 3}')
    'matching': (bindings) ->
      assert.equal bindings.a.name, 'blah'
      assert.equal bindings.b.value, 3

  ## TODO: only current failing test
  #
  # 'match on object with specific property':
  #   topic: ->
  #     m('{food: @a}', '{blah: 3, food: "apple"}')
  #   'matching': (bindings) ->
  #     assert.equal bindings.a.value, "apple"

  'match on object +':
    topic: ->
      m('asdf(@a+)', 'asdf(1, "abc", 200)')
    'matching': (bindings) ->
      assert.ok bindings.a
      assert.equal bindings.a.length, 3
      assert.equal bindings.a[0].value, 1
      assert.equal bindings.a[1].value, 'abc'
      assert.equal bindings.a[2].value, 200

  'match on object no plus':
    topic: ->
      m('asdf(@a)', 'asdf(1, "abc", 200)')
    'matching': (bindings) ->
      assert.ok bindings.a
      assert.equal bindings.a.value, 1

  'only match if the object property is cookie':
    topic: ->
      m('@a.@b = @c', 'blah.asdf = 3', (name, node) ->
        if name == 'b' && node.name != 'cookie'
          return false
        return true
      )
    'should not match bindings': (bindings) ->
      assert.equal bindings, null

  'conversion to literal is not supported':
    topic: ->
      r('@a[@b] = @c', "method(@a, @b, @c)")
    'should leave internal representation of literals alone': (convert) ->
      assert.equal convert('blah[something] = 2'), "method(blah, something, 2);"

  'conversion to literal is supported with conversion function':
    topic: ->
      r('@a[@b] = @c', "method(@a, @b, @c)", null, (binding, node) ->
        if node.name == 'b'
          if binding.type == 'Identifier'
            {type: 'Literal', value: binding.name}
      )
    'should convert identifiers but leave expressions alone': (convert) ->
      assert.equal convert('blah[abc] = 2'), "method(blah, 'abc', 2);"
      assert.equal convert("blah['string'] = 2"), "method(blah, 'string', 2);"
      assert.equal convert('blah[1+1] = 2'), "method(blah, 1 + 1, 2);"

  'only match if the property is not a number':
    topic: ->
      m('@a[@b] = @c', 'blah[0] = 3', (name, node) ->
        if name == 'b' && node.name == undefined
          return false
        return true
      )
    'should not match bindings': (bindings) ->
      assert.equal bindings, null

  'only match if the object property is location':
    topic: ->
      m('@a.@b = @c', 'blah.location = 3', (name, node) ->
        if name == 'b' && node.name != 'location'
          return false
        return true
      )
    'should match bindings': (bindings) ->
      assert.equal bindings.b.name, 'location'

  'basic replacements':
    topic: ->
      r("@a.@b = @c", "assignment( @a, @b, @c )")
    'should work': (convert) ->
      assert.equal convert('window.location = 3;'), 'assignment(window, location, 3);'
      assert.equal convert("window.location = 'google.com';"), "assignment(window, location, 'google.com');"
      assert.equal convert("a.b= function(){};"), "assignment(a, b, function () {\n});"

  'basic replacements for method':
    topic: ->
      r("@method(@a)", "blah( @method, @a )")
    'should work': (convert) ->
      assert.equal convert("fruit('apple')"), "blah(fruit, 'apple');"

  'ensure it compares computed for MemberExpressions':
    topic: ->
      r("@a.@b = @c", "asdf( @a, @b, @c )")
    'should work': (convert) ->
      assert.equal convert("a.b = c"), "asdf(a, b, c);"
      assert.equal convert("a[b] = c"), "a[b] = c;"

.export(module)
