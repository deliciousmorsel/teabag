class Teabag.Reporters.HTML extends Teabag.Reporters.BaseView

  constructor: ->
    @start = Date.now()
    @config = {"use-catch": true, "build-full-report": false, "display-progress": true}
    @total = {exist: 0, run: 0, passes: 0, failures: 0, skipped: 0}
    @views = {specs: {}, suites: {}}
    @elements = {}
    @filter = false
    @readConfig()
    super


  build: ->
    @el = @findEl("report-all")
    @setText("env-info", @envInfo())
    @findEl("toggles").onclick = @toggleConfig
    @showConfiguration()
    @buildProgress()


  buildProgress: ->
    if !@config["display-progress"]
      @setHtml("progress", "<div></div>")
      @setClass("progress", "")
      return
    try
      canvas = @findEl("progress-canvas")
      canvas.width = 80
      canvas.height = 80
      canvas.style.width = 80
      canvas.style.height = 80
      @ctx = canvas.getContext("2d")
    catch e # intentionally do nothing


  reportRunnerStarting: (runner) ->
    @total.exist = runner.total || runner.specs().length
    @setText("stats-duration", "...") if @total.exist


  reportSpecStarting: (spec) ->
    spec = new Teabag.Reporters.NormalizedSpec(spec)
    @reportView = new Teabag.Reporters.HTML.SpecView(spec, @) if @config["build-full-report"]
    @specStart = Date.now()


  reportSpecResults: (spec) ->
    @total.run += 1
    @updatePercent()
    @updateStatus(spec)


  updateStatus: (spec) ->
    spec = new Teabag.Reporters.NormalizedSpec(spec)
    result = spec.result()

    if result.skipped || result.status == "pending"
      @updateStat("skipped", @total.skipped += 1)
      return

    elapsed = Date.now() - @specStart

    if result.status == "passed"
      @updateStat("passes", @total.passes += 1)
      @reportView?.updateState("passed", elapsed)
    else
      @updateStat("failures", @total.failures += 1)
      @reportView?.updateState("failed", elapsed)
      new Teabag.Reporters.HTML.FailureView(spec).appendTo(@findEl("report-failures")) unless @config["build-full-report"]
      @setStatus("failed")


  reportRunnerResults: =>
    return unless @total.run
    @setText("stats-duration", "#{((Date.now() - @start) / 1000).toFixed(3)}s")
    @setStatus("passed") unless @total.failures
    @setText("stats-passes", @total.passes)
    @setText("stats-failures", @total.failures)
    @setText("stats-skipped", @total.skipped)
    if @total.run < @total.exist
      @total.skipped = @total.exist - @total.run
      @total.run = @total.exist
    @setText("stats-skipped", @total.skipped)
    @updatePercent()


  showConfiguration: ->
    @setClass(key, if value then "active" else "") for key, value of @config


  updateStat: (name, value, force = false) ->
    return unless @config["display-progress"]
    @setText("stats-#{name}", value)


  updatePercent: ->
    return unless @config["display-progress"]
    percent = if @total.exist then Math.ceil((@total.run * 100) / @total.exist) else 0
    @setHtml("progress-percent", "#{percent}%")
    return unless @ctx
    size = 80
    half = size / 2
    @ctx.strokeStyle = "#fff"
    @ctx.lineWidth = 1.5
    @ctx.clearRect(0, 0, size, size)
    @ctx.beginPath()
    @ctx.arc(half, half, half - 1, 0, Math.PI * 2 * (percent / 100), false)
    @ctx.stroke()


  setStatus: (status) ->
    document.body.className = "teabag-#{status}"


  setFilter: (filter) ->
    return unless filter
    @setClass("filtered", "teabag-filtered")
    @setHtml("filtered", "#{filter}", true)


  readConfig: ->
    @config = config if config = @cookie("teabag")


  toggleConfig: (e) =>
    button = e.target
    return unless button.tagName.toLowerCase() == "button"
    name = button.getAttribute("id").replace(/^teabag-/, "")
    @config[name] = !@config[name]
    @cookie("teabag", @config)
    window.location.href = window.location.href


  cookie: (name, value = undefined) ->
    if value == undefined
      name = name.replace(/([.*+?^=!:${}()|[\]\/\\])/g, "\\$1")
      match = document.cookie.match(new RegExp("(?:^|;)\\s?#{name}=(.*?)(?:;|$)", "i"))
      match && JSON.parse(unescape(match[1]).split(" ")[0])
    else
      date = new Date()
      date.setDate(date.getDate() + 365)
      document.cookie = "#{name}=#{escape(JSON.stringify(value))}; path=/; expires=#{date.toUTCString()};"



class Teabag.Reporters.HTML.FailureView extends Teabag.Reporters.BaseView

  constructor: (@spec) ->
    super


  build: ->
    super("spec")
    html = """<h1 class="teabag-clearfix"><a href="#{@spec.link}">#{@spec.fullDescription}</a></h1>"""
    for error in @spec.errors()
      html += """<div>#{error.stack || error.message || "Stack trace unavailable"}</div>"""
    @el.innerHTML = html



class Teabag.Reporters.HTML.SpecView extends Teabag.Reporters.BaseView

  viewId = 0

  constructor: (@spec, @reporter) ->
    @views = @reporter.views
    @spec.viewId = viewId += 1
    @views.specs[@spec.viewId] = @
    super


  build: ->
    classes = ["spec"]
    classes.push("state-pending") if @spec.pending
    super(classes.join(" "))
    @el.innerHTML = """<a href="#{@spec.link}">#{@spec.description}</a>"""
    @parentView = @buildParent()
    @parentView.append(@el)


  buildParent: ->
    parent = @spec.parent
    if parent.viewId
      @views.suites[parent.viewId]
    else
      view = new Teabag.Reporters.HTML.SuiteView(parent, @reporter)
      @views.suites[view.suite.viewId] = view


  buildErrors: ->
    div = @createEl("div")
    html = ""
    for error in @spec.errors()
      html += """#{error.stack || error.message || "Stack trace unavailable"}"""
    div.innerHTML = html
    @append(div)


  updateState: (state, elapsed) ->
    result = @spec.result()
    classes = ["state-#{state}"]
    classes.push("slow") if elapsed > Teabag.slow
    @el.innerHTML += "<span>#{elapsed}ms</span>" unless state == "failed"
    @el.className = classes.join(" ")
    @buildErrors() unless result.status == "passed"
    @parentView.updateState?(state)



class Teabag.Reporters.HTML.SuiteView extends Teabag.Reporters.BaseView

  viewId = 0

  constructor: (@suite, @reporter) ->
    @views = @reporter.views
    @suite.viewId = viewId += 1
    @views.suites[@suite.viewId] = @
    @suite = new Teabag.Reporters.NormalizedSuite(suite)
    super


  build: ->
    super("suite")
    @el.innerHTML = """<h1><a href="#{@suite.link}">#{@suite.description}</a></h1>"""
    @parentView = @buildParent()
    @parentView.append(@el)


  buildParent: ->
    parent = @suite.parent
    return @reporter unless parent
    if parent.viewId
      @views.suites[parent.viewId]
    else
      view = new Teabag.Reporters.HTML.SuiteView(parent, @reporter)
      @views.suites[view.suite.viewId] = view


  append: (el) ->
    super(@ol = @createEl("ol")) unless @ol
    @ol.appendChild(el)


  updateState: (state) ->
    return if @state == "failed"
    @el.className = "#{@el.className.replace(/\s?state-\w+/, "")} state-#{state}"
    @parentView.updateState?(state)
    @state = state