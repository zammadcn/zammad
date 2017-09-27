class App.Auth

  @login: (params) ->
    App.Log.debug 'Auth', 'login', params
    params.data['fingerprint'] = App.Browser.fingerprint()
    App.Ajax.request(
      id:     'login'
      type:   'POST'
      url:    App.Config.get('api_path') + '/signin'
      data:   JSON.stringify(params.data)
      success: (data, status, xhr) =>

        # set login (config, session, ...)
        @_login(data)

        # execute callback
        params.success(data, status, xhr)

      error: (xhr, statusText, error) =>
        @_loginError()
        params.error(xhr, statusText, error)
    )

  @loginCheck: (callback) ->
    params =
      fingerprint: App.Browser.fingerprint()
    App.Log.debug 'Auth', 'loginCheck'
    App.Ajax.request(
      id:    'login_check'
      async: false
      type:  'POST'
      url:   App.Config.get('api_path') + '/signshow'
      data:  JSON.stringify(params)
      success: (data, status, xhr) =>

        # set login (config, session, ...)
        @_login(data, 'check')

        if callback
          callback()

      error: (xhr, statusText, error) =>
        @_loginError()
    )

  @logout: ->
    App.Log.debug 'Auth', 'logout'
    App.Ajax.request(
      id:   'logout'
      type: 'DELETE'
      url:  App.Config.get('api_path') + '/signout'
      success: =>

        # set logout (config, session, ...)
        @_logout()

      error: (xhr, statusText, error) =>
        @_loginError()
    )

  @_login: (data, type) ->
    App.Log.debug 'Auth', '_login:success', data

    # if session is not valid
    if data.error

      # update config
      for key, value of data.config
        App.Config.set(key, value)

      # refresh default collections
      if data.collections
        App.Collection.resetCollections(data.collections)

      # empty session
      App.Session.init()

      # update model definition (needed for not authenticated areas like wizard)
      @_updateModelAttributes(data.models)

      # set locale
      locale = window.navigator.userLanguage || window.navigator.language || 'en-us'
      App.i18n.set(locale)

      # rebuild navbar with new navbar items
      App.Event.trigger('auth')
      App.Event.trigger('auth:logout')
      App.Event.trigger('ui:rerender')
      App.TaskManager.tasksInitial()
      return false

    # clear local store
    if type isnt 'check'
      App.Event.trigger('clearStore')

    # update model definition
    @_updateModelAttributes(data.models)

    # update config
    for key, value of data.config
      App.Config.set(key, value)

    # refresh default collections
    if data.collections
      App.Collection.resetCollections(data.collections)

    # load assets
    if data.assets
      App.Collection.loadAssets(data.assets)

    # store user data
    sessionUser = App.User.fullLocal(data.session.id)
    App.Session.set(sessionUser)

    # trigger auth ok with new session data
    App.Event.trigger('auth', data.session)

    # init of i18n
    preferences = App.Session.get('preferences')
    if preferences && preferences.locale
      locale = preferences.locale
    if !locale
      locale = window.navigator.userLanguage || window.navigator.language || 'en-us'
    App.i18n.set(locale)

    App.Event.trigger('auth:login', data.session)
    App.Event.trigger('ui:rerender')
    App.TaskManager.tasksInitial()

  @_updateModelAttributes: (models) ->
    return if _.isEmpty(models)

    for model, attributes of models
      if App[model]
        if _.isFunction(App[model].updateAttributes)
          App[model].updateAttributes(attributes)

  @_logout: (rerender = true) ->
    App.Log.debug 'Auth', '_logout'

    App.Ajax.abortAll()
    App.TaskManager.reset()
    App.Session.init()

    App.Event.trigger('auth')
    App.Event.trigger('auth:logout')
    if rerender
      window.location.href = '#login'
      App.Event.trigger('ui:rerender')
    App.Event.trigger('clearStore')

    # clear all in-memory data of all App.Model's
    for model_key, model_object of App
      if _.isFunction(model_object.resetCallbacks)
        model_object.resetCallbacks()
      if _.isFunction(model_object.resetAttributes)
        model_object.resetAttributes()
      if _.isFunction(model_object.clearInMemory)
        model_object.clearInMemory()

  @_loginError: ->
    App.Log.debug 'Auth', '_loginError:error'

    # empty session
    App.Session.init()

    # rebuild navbar
    App.Event.trigger('auth')
    App.Event.trigger('auth:logout')
    App.Event.trigger('ui:rerender')
    App.Event.trigger('clearStore')
