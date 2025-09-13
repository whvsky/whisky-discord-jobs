Config = Config or {}

Config.Debug = false -- set true if you want to see debug prints
Config.AllowNoDiscord = true
Config.ResetBeforeGrant = true
Config.BaseAce = "group.member"
Config.AutoGrantDepartmentAce = true
Config.EnableJobLink = true
Config.OnlySetIfUnemployed = false

Config.DepartmentPriority = {
  'group.lspd',
  'group.bcso',
  'group.sahp',
}

-- Fill out your ladders here
Config.DepartmentMap = {
  ['group.lspd'] = {
    job = 'lspd',
    defaultGrade = 0,
    roleGrades = {
        ["ROLEID"] = 0, -- Police Cadet → Recruit
        ["ROLEID"] = 1, -- Police Officer → Officer
        ["ROLEID"] = 1, -- Police Officer First Class → Officer
        ["ROLEID"] = 1, -- Senior Police Officer → Officer
        ["ROLEID"] = 1, -- Corporal → Officer
        ["ROLEID"] = 2, -- Supervisor In Training → Leadership
        ["ROLEID"] = 2, -- Supervisor Staff → Leadership
        ["ROLEID"] = 3, -- Command Staff → Supervisor
        ["ROLEID"] = 4, -- Department Heads → Command
        ["ROLEID"] = 5, -- Deputy Chief Of Police
        ["ROLEID"] = 6, -- Assistant Chief
        ["ROLEID"] = 7, -- Chief of Police (isboss)
    },
    groupGrades = {
      -- ["group.lspd_chief"] = 7,
    }
  },
  ['group.bcso'] = { job = 'bcso', defaultGrade = 0, roleGrades = {}, groupGrades = {} },
  ['group.sahp'] = { job = 'sahp', defaultGrade = 0, roleGrades = {}, groupGrades = {} },
}
