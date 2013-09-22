# Moves sunday back to last index
# 0 -> 6
# 1 -> 0
# 2 -> 1
# 3 -> 2, etc
moveSundayBack = (index)->
  if index is 0
    6
  else
    index - 1

# Input is an integer representing the target week.
# 0 -> current week
# 1 -> next week
# -1 -> last week
# Returns an ordered list of name, timestamp hashes
buildData = (which)->
  secondsPerDay = 86400
  now = new Date()
  start = new Date(now.getFullYear(), now.getMonth(), now.getDate())
  # today's floored unix timestamp
  timestamp = start / 1000
  # today's day index
  dayNumber = moveSundayBack(now.getDay())
  # move this back to the last monday
  mondayTimestamp = timestamp - (dayNumber) * secondsPerDay

  # make bucket for every day, but leave task aggregating to the days
  buckets = [
    {'name':'','timestamp':0},
    {'name':'','timestamp':0},
    {'name':'','timestamp':0},
    {'name':'','timestamp':0},
    {'name':'','timestamp':0},
    {'name':'','timestamp':0},
    {'name':'','timestamp':0}
  ]

  firstIndex = 0 + 7 * which
  lastIndex = firstIndex + 6

  # add timestamps to buckets
  for count in [firstIndex..lastIndex]
    buckets[count%7]['timestamp'] = mondayTimestamp + count * secondsPerDay

  # add day names to buckets
  dayNames = getDayNames(buckets[0]['timestamp']*1000)
  for day in [0..6]
    # TODO support negative week indices by adding to this modulus
    buckets[day%7]['name'] = dayNames[day]

  buckets

getDayNames = (mondayTimestamp)->
  msPerDay = 86400000
  weekdays = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
  dayNames = []
  currentDate = new Date(mondayTimestamp)

  for x in [0..6]
    dayName = weekdays[moveSundayBack(currentDate.getDay())]
    dayMonth = currentDate.getMonth() + 1
    dayDate = currentDate.getDate()
    name = dayName + " " + dayMonth + "/" + dayDate
    dayNames.push(name)
    # go to tomorrow
    currentDate = new Date(currentDate.getTime() + msPerDay)

  dayNames

Template.homePage.helpers(
  # Return ordered list of day names and timestamps [{'name':'Monday 10/26','timestamp':'13244653982'},{},{}...]
  firstWeek: ()->
    buildData(0)

  secondWeek: ()->
    buildData(1)

)

Template.homePage.events(
  # take all the tasks in these two weeks
  # place them intelligently into plans for this week
  'click .autoplan': (e)->
    # get two weeks of tasks
    secondsPerDay = 86400
    now = new Date()
    start = new Date(now.getFullYear(), now.getMonth(), now.getDate())
    # today's floored unix timestamp
    timestamp = start / 1000
    # today's day index
    dayNumber = moveSundayBack(now.getDay())
    # move this back to the last monday
    weekBeginning = timestamp - (dayNumber) * secondsPerDay
    weekEnd = weekBeginning + 7*secondsPerDay

    nextBeginning = weekBeginning + 7*secondsPerDay
    nextEnd = weekEnd + 7*secondsPerDay

    firstWeekQuery = { dueDate: { $gte: weekBeginning, $lt: weekEnd} }
    secondWeekQuery = { dueDate: { $gte: nextBeginning, $lt: nextEnd}}

    firstWeekTasks = Tasks.find(firstWeekQuery, { sort: { due: -1 } }).fetch()
    secondWeekTasks = Tasks.find(secondWeekQuery, {sort: { due: -1}}).fetch()

    # get this week's plans
    plansQuery = { timestamp: { $gte: weekBeginning, $lt: weekEnd} }
    currentPlans = Plans.find(firstWeekQuery, {sort: { timestamp: -1 }}).fetch()

    # build buckets and put plans into the buckets
    buckets = [
      {timestamp:0,plans:[]},
      {timestamp:0,plans:[]},
      {timestamp:0,plans:[]},
      {timestamp:0,plans:[]},
      {timestamp:0,plans:[]},
      {timestamp:0,plans:[]},
      {timestamp:0,plans:[]},
    ]
    bucketMap = {}
    for i in [0..6]
      ts = weekBeginning + i*secondsPerDay
      buckets[i].timestamp = ts
      bucketMap[ts] = i
    for plan in currentPlans
      for bucket in buckets
        if plan.timestamp is bucket.timestamp
          bucket.plans.push(plan)

    # FIRST WEEK
    for task in firstWeekTasks
      # how many plans already exist?
      relevantPlans = []
      for plan in currentPlans
        if plan.taskId is task._id
          relevantPlans.push(plan)
      # is n*2 hours < estimated time of task?
      # if so, make another plan and place it according to the following heuristic
      # if buckets before due date are evenly full, place in earlier bucket
      # if buckets before due date are not evenly full, place in less full bucket
      while relevantPlans.length * 2 * 3600 < task.duration
        # check if the buckets before the due date are evenly full
        even = true
        leastFull = 0
        shortest = 10000
        for i in [0...bucketMap[task.dueDate]]
          len = buckets[i].plans.length
          if len isnt buckets[0].plans.length
            even = false
          if len < shortest
            shortest = len
            leastFull = i

        if even
          # prioritize earlier
          info =
            id: task._id
            timestamp: buckets[0].timestamp
          buckets[0].plans.push('new plan')
        else
          # prioritize least full
          info =
            id: task._id
            timestamp: buckets[leastFull].timestamp
          buckets[leastFull].plans.push('new plan')

        Meteor.call('makePlan', info, (error, id)->
          if error
            Meteor.Errors.throw(error.reason)

            if error.error is 302
              Meteor.Router.to('home', error.details)
        )

        relevantPlans.push('new plan')

    # SECOND WEEK
    # fill in friday, saturday, sunday with big projects and monday, then fill up to the average of the week
    # find average plans / day in first week
    tot = 0
    for i in [0..3]
      tot += buckets[i].plans.length
    avg = Math.max(Math.floor(tot / 4), 3)

    # find all monday tasks, then tasks >3 hours in second week
    queued = []
    for task in secondWeekTasks
      if task.dueDate is nextEnd or task.duration > 10800
        queued.push(task)
    while Math.floor((buckets[4].plans.length + buckets[5].plans.length + buckets[6].plans.length)/3) < avg and queued.length > 0
      thisTask = queued.shift()
      even = true
      leastFull = 0
      shortest = 10000
      for i in [4..6]
        len = buckets[i].plans.length
        if len isnt buckets[4].plans.length
          even = false
        if len < shortest
          shortest = len
          leastFull = i

      if even
        # prioritize earlier
        info =
          id: thisTask._id
          timestamp: buckets[4].timestamp
        buckets[4].plans.push('new plan')
      else
        # prioritize least full
        info =
          id: thisTask._id
          timestamp: buckets[leastFull].timestamp
        buckets[leastFull].plans.push('new plan')

      Meteor.call('makePlan', info, (error, id)->
        if error
          Meteor.Errors.throw(error.reason)

          if error.error is 302
            Meteor.Router.to('home', error.details)
      )


    # fill in tasks until each day is up to the floored average
    # prioritize monday > early long > late long
)
