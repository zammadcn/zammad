class Index extends App.ControllerSubContent
  requiredPermission: 'admin.channel_sms'

  elements:
    '.js-testButton':       'testButton'
    '.js-submit':           'submitButton'
    'select[name=adapter]': 'adapterSelect'
    '.zammad-switch input': 'switchButtonInput'

  events:
    'click  .js-delete':             'onDelete'
    'click  .js-channelAdd':         'onAdd'
    'submit .js-channelForm':        'onSubmit'
    'click  .js-testButton':         'onTest'
    'change .js-channelForm select': 'onAdapterChange'
    'change .zammad-switch input':   'onSwitch'
    'keyup  .js-channelInput':       'setTestAndSaveButtonState'

  constructor: ->
    super
    @load()

  load: =>
    @startLoading()

    @ajax(
      type: 'GET'
      url:  "#{@apiPath}/channels_sms"
      success: (data) =>
        @stopLoading()
        @configuration = data.configuration
        App.Collection.loadAssets(data.data.assets)
        @render(data.data)
    )

  render: (data) ->
    if channel_id = data.channel_ids[0]
      @channel = App.Channel.find(channel_id)
    else
      @channel = new App.Channel(active: false)

    element = $(App.view('channel/sms')(@))
    @html(element)
    @applyChannel(@channel)

  applyChannel: (channel) ->

    adapter = channel?.options?.adapter || ''

    @el.find('.js-channelInput').val(adapter)

    @switchButtonInput.prop('checked', @isSwitchOn())
    @switchButtonInput.prop('disabled', @isSwitchDisabled())

    for own key, value of channel?.options || ''
      @el.find(".js-channelInput[name=#{key}]").val(value)

    @updateForAdapter(channel?.options?.adapter || '', channel)

  onTest: (e) ->
    e.preventDefault()
    new TestModal(@formParam(@el))

  onAdd: (e) ->
    e.preventDefault()

    @channel = new App.Channel(active: false)
    @applyChannel(@channel)

  onSwitch: (e) ->
    @formDisable(e)

    url = "#{@apiPath}/channels_sms/#{@channel.id}/"
    url += if @channel.active then 'disable' else 'enable'

    @el.find('.alert').addClass('hide')

    @ajax(
      type: 'POST'
      url: url
      success: (data) =>
        @el.find('.alert').addClass('hide')
        @channel.load(data)
        @formEnable(e)
        @applyChannel(@channel)
      error: (xhr) =>
        data = JSON.parse(xhr.responseText)
        @formEnable(e)
        @el.find('.alert').removeClass('hide').text(@T(data.error || 'Unable to save channel'))
    )

  onDelete: ->
    if @channel.isNew()
      @executeDelete()
      return

    new App.ControllerConfirm(
      message: 'Are you sure to delete the SMS provider?'
      callback: @executeDelete
      container: @el.closest('.content')
    )

  executeDelete: =>
    if @channel.isNew()
      @channel = new App.Channel(active: false)
      @applyChannel(@channel)
      return

    @startLoading()
    @formDisable(@el)

    @ajax(
      type: 'DELETE'
      url:  "#{@apiPath}/channels_sms/#{@channel.id}"
      success: (data) =>
        @stopLoading()
        App.Channel.destroy(@channel.id, ajax: false)
        @channel = new App.Channel(active: false)
        @formEnable(@el)
        @applyChannel(@channel)
      error: (xhr) =>
        data = JSON.parse(xhr.responseText)
        @formEnable(e)
        @el.find('.alert').removeClass('hide').text(@T(data.error || 'Unable to delete channel'))
    )

  onSubmit: (e) ->
    e.preventDefault()

    if @adapterSelect.val() is ''
      @onDelete()
      return

    @formDisable(e)

    url = "#{@apiPath}/channels_sms"

    if @channel and not @channel.isNew()
      url += "/#{@channel.id}"
      ajax_method = 'PUT'
    else
      ajax_method = 'POST'

    @el.find('.alert').addClass('hide')

    @ajax(
      type: ajax_method
      url: url
      data: JSON.stringify(@formParam(@el))
      success: (data) =>
        @channel.load(data)

        if @channel.isNew()
          App.Channel.addRecord(@channel)

        @formEnable(e)
        @applyChannel(@channel)
      error: (xhr) =>
        data = JSON.parse(xhr.responseText)
        @formEnable(e)
        @el.find('.alert').removeClass('hide').text(@T(data.error || 'Unable to save channel'))
    )

  renderProvider: (element) ->
    options = _.reduce(_.keys(@configuration), (memo, elem) =>
      memo[elem] = @configuration[elem].name
      memo
    , {})

    selection = App.UiElement.select.render(
      name: 'adapter'
      id: 'form-adapter'
      multiple: false
      nulloption: true
      null: true
      options: options
      value: @channel?.options?.adapter
    )

    selection[0].outerHTML

  onAdapterChange: (e) ->
    @updateForAdapter(e.target.value)

  updateForAdapter: (adapter, channel) ->
    @adapterSelect.val(adapter)

    @el.find('fieldset .form-group:has(.js-channelInput)').remove()

    if _.isObject(@configuration[adapter])
      for field in @configuration[adapter].fields
        value = if _.isObject(channel) then channel.options[field.identifier] else ''

        elem = App.view('channel/sms_field')({context: @, data: field, value: value})
        @el.find('fieldset').append(elem)

    if adapter is '' || @channel?.isNew() isnt false
      @switchButtonInput.attr('disabled', true)
    else
      @switchButtonInput.removeAttr('disabled')

    @setTestAndSaveButtonState()

  isSwitchOn: ->
    !@isSwitchDisabled() && @channel.active is true

  isSwitchDisabled: ->
    @channel.isNew()

  setTestAndSaveButtonState: ->
    if @testAndSavePossible()
      @testButton.removeAttr('disabled')
      @submitButton.removeAttr('disabled')
    else
      @testButton.attr('disabled', true)
      @submitButton.attr('disabled', true)

  testAndSavePossible: ->
    if @adapterSelect.val() == ''
      return false

    visible_fields = @el.find('.js-channelForm .input:not(.hide) input:required')
    empty_fields   = visible_fields.filter((i, elem) -> $(elem).val() == '')

    return empty_fields.size() == 0

class TestModal extends App.ControllerModal
  elements:
    'form': 'form'

  head: 'Test SMS provider'

  buttonCancel: true

  constructor: (adapterData) ->
    super
    @adapterData = adapterData

  content: ->
    App.view('channel/sms_test')(@)

  submit: (e) ->
    super(e)

    @el.find('.alert').addClass('hide')
    @formDisable(@el)

    testData = _.extend(
      @formParam(@form),
      @adapterData
    )

    @ajax(
      type: 'POST'
      url:  "#{@apiPath}/channels_sms/test"
      data: JSON.stringify(testData)
      processData: true
      success: (data) =>
        @formEnable(@el)
        if error_text = (data.error || data.error_human)
          @el.find('.alert--danger')
            .text(@Ti(error_text))
            .removeClass('hide')
        else
          @el.find('.alert--success')
            .text(@T('SMS successfully sent'))
            .removeClass('hide')
      error: (xhr) =>
        data = JSON.parse(xhr.responseText)
        @formEnable(@el)
        @el.find('.alert--danger')
          .text(@T(data.error || 'Unable to perform test'))
          .removeClass('hide')
    )

App.Config.set('SMS', { prio: 3100, name: 'SMS', parent: '#channels', target: '#channels/sms', controller: Index, permission: ['admin.channel_sms'] }, 'NavBarAdmin')
