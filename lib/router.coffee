Router.configure
  before: clearErrors
  loadingTemplate: 'loading'
  layoutTemplate: 'layout'
  # waitOn: ->
  #   return [Meteor.subscribe('notifications')]

Router.map ->
  @route 'landingPage',
    layoutTemplate: 'layout'
    loadingTemplate: 'loading'
    path: '/'
    action: ()->
      if Meteor.user()
        @render 'homePage'
      else
        if Meteor.loggingIn()
          @render @loadingTemplate
        else
          @render 'landingPage'

  @route 'settings',
    path: '/settings'

  @route 'loginPage',
    path: '/login'
    layoutTemplate: 'layout'
    before: ->
      Session.set('entryError', undefined)
      Session.set('buttonText', 'in')

  @route "registerPage",
    path: "/register"
    before: ->
      Session.set('entryError', undefined)
      Session.set('buttonText', 'up')

  @route 'logout',
    path: '/logout'
    before: ->
      Session.set('entryError', undefined)
      if AccountsEntry.settings.homeRoute
        Meteor.logout()
        Router.go AccountsEntry.settings.homeRoute
      @stop()

  @route 'aboutPage',
    path: '/about'

  @route 'not_found',
    path: '*'

clearErrors = ()->
  Errors.clearSeen()

requireLogin = ()->
  unless Meteor.user()
    if Meteor.loggingIn()
      @render @loadingTemplate
    else
      @redirect 'landingPage'

    @stop()

Router.before(()-> clearErrors())
