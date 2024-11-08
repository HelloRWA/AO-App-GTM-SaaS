-- A ERC20 like token in AO
-- the contract's basic informations
local json = require("json")
local bint = require('.bint')(256)
local pretty = require(".pretty")
local Helper = {
  isOwner = function(msg)
    return msg.From == ao.env.Process.Owner
  end,
  log = function(debugTag, msg, data)
    if (msg.debug == nil) then
      return
    end
    -- TODO: filter prefix:* pattern
    if (msg.debug ~= debugTag) then
      return
    end
    if type(data) == 'table' then
      print(pretty.tprint(data, 2))
    else
      print(data)
    end
  end
}

local formatted = pretty.tprint({
  name = "John Doe",
  age = 22,
  friends = { "Maria", "Victor" }
}, 2)

-- prints the formatted table structure
print(formatted)

-- there data here should be const after deploy
Info = Info or {
  version = "1.0.0",
  name = "Snake",
  symbol = "SNK",
  decimals = 18
}

-- Add this constant at the top of the file, after the Info table
local NEW_USER_BONUS = '5' -- 5 SNK coins for new users

-- the contract's states
States = States or {
  paymentList = {},
  totalSupply = 0,
  totalPlayers = 0,
  prizesPool = 0,
  balances = {},
  allowances = {},
  userLastGamePlayId = {},
  adminTable = {},
  gamePlays = {},
  userTotalScore = {},
  leaderboard = {}, -- New leaderboard state
  nicknames = {},   -- New nicknames state
  inviteCodeBalance = '0',
  inviteCodePaidCount = {}
}

-- the methods, which only used inside the contract, the functions defined here internd to be re-used in multiple UserActions
-- suggested to write methods in UserActions first, if you find some methods are frequently used, you can put them here
Methods = Methods or {}

Methods.resetHandlers = function()
  for _, o in ipairs(Handlers.list) do
    if o.name ~= "_default" and o.name ~= "_eval" then
      print("remove " .. o.name)
      Handlers.remove(o.name)
    end
  end
  print(Handlers.list)
end

Methods.resetAllUsers = function()
  States.totalSupply = 0
  States.userLastGamePlayId = {}
  States.gamePlays = {}
  States.userTotalScore = {}
  States.leaderboard = {}
  States.nicknames = {}
end

Methods.allowance = function(owner, spender)
  return States.allowances[owner][spender] or '0'
end

-- Helper function to update leaderboard
Methods.updateLeaderboard = function(playerAddress, score)
  local leaderboard = States.leaderboard
  local playerEntry = {
    address = playerAddress,
    score = score,
    nickname = States.nicknames[playerAddress] or playerAddress -- Use nickname if set, otherwise use address
  }

  -- Remove existing entry for the player if present
  for i, entry in ipairs(leaderboard) do
    if entry.address == playerAddress then
      table.remove(leaderboard, i)
      break
    end
  end

  -- Insert new entry and sort
  table.insert(leaderboard, playerEntry)
  table.sort(leaderboard, function(a, b) return bint(a.score) > bint(b.score) end)

  -- Keep only top 10
  while #leaderboard > 10 do
    table.remove(leaderboard)
  end

  States.leaderboard = leaderboard
end

Methods.getInviteCodePrice = function()
  return '100'
end

Methods.updateBalance = function(user, action, amount)
  local balance = bint(States.balances[user] or '0')
  if action == 'mint' then
    States.balances[user] = tostring(balance + amount)
    States.totalSupply = tostring(bint(States.totalSupply) + bint(amount))
  else
    States.balances[user] = tostring(balance - amount)
    States.totalSupply = tostring(bint(States.totalSupply) + bint(amount))
  end
end

-- the UserActions, which can be called by other contracts via the `Send` function with "Action" param
UserActions = UserActions or {}

UserActions.name = function()
  return Info.name
end

UserActions.symbol = function()
  return Info.symbol
end

UserActions.decimals = function()
  return Info.decimals
end

UserActions.totalSupply = function()
  return States.totalSupply
end

UserActions.balanceOf = function(msg)
  local account = msg.Tags.account
  if (account == nil) then
    account = msg.From
  end

  return States.balances[account] or '0'
end

UserActions.transfer = function(msg)
  local from = msg.From
  if (msg.Data.from) then
    from = msg.Data.from
  end

  local to = msg.Data.to
  local value = msg.Data.value
  assert(type(to) == 'string', "to is required!")
  assert(type(value) == 'string', "value is required!")

  value = bint(value)
  assert(bint('0') < value, 'value must be greater than 0')

  local balance = bint(States.balances[from])
  assert(balance >= value, "insufficient balance")

  States.balances[from] = tostring(balance - value)
  States.balances[to] = tostring(bint(States.balances[to] or '0') + value)

  return true
end

UserActions.allowance = function(msg)
  local owner = msg.Data.owner
  local spender = msg.Data.spender
  return Methods.allowance(owner, spender)
end

UserActions.approve = function(msg)
  local owner = msg.From
  local spender = msg.Data.spender
  local value = msg.Data.value

  States.allowances[owner][spender] = value
  return true
end

UserActions.stats = function(msg)
  local balance = '0'
  local user = msg.Tags.user
  if user ~= nil then
    print('user: ' .. user .. ' balance: ' .. balance)
    balance = States.balances[user] or '0'
  end

  print(user)
  print(States.balances)

  return {
    balance = balance,
    totalSupply = States.totalSupply,
    prizesPool = States.prizesPool,
    totalPlayers = States.totalPlayers,
  }
end

UserActions.Info = function()
  local function getKeys(t)
    local keys = {}
    for key, _ in pairs(t) do
      table.insert(keys, key)
    end
    return keys
  end

  return {
    Info = Info,
    States = getKeys(States),
    Methods = getKeys(Methods),
    UserActions = getKeys(UserActions),
    ContractActions = getKeys(ContractActions),
  }
end

UserActions.GenerateGamePlayId = function(msg)
  local playerAddress = msg.From
  -- Get the last game play ID for this user, or nil if it's their first game
  local lastId = States.userLastGamePlayId[playerAddress]
  local isNewUser = lastId == nil

  if not isNewUser and lastId ~= 0 then
    local lastGame = States.gamePlays[tostring(playerAddress) .. "-" .. tostring(lastId)]
    if (lastGame ~= nil and lastGame.status ~= "ended") then
      return {
        gamePlayId = lastId
      }
    end
  end

  local balance = bint(States.balances[playerAddress] or '0')

  if isNewUser then
    -- Give new user the bonus SNK coins
    balance = balance + bint(NEW_USER_BONUS)
    States.balances[playerAddress] = tostring(balance)
    States.totalSupply = tostring(bint(States.totalSupply) + bint(NEW_USER_BONUS))
  end

  -- Charge 1 SNK for playing
  assert(balance >= bint('1'), "Insufficient SNK balance. You need at least 1 SNK to play.")
  balance = balance - bint('1')
  States.balances[playerAddress] = tostring(balance)

  local gamePlayId = (lastId or 0) + 1
  -- Update the last used ID for this user
  States.userLastGamePlayId[playerAddress] = gamePlayId

  -- Store the game play information
  States.gamePlays = States.gamePlays or {}
  States.gamePlays[tostring(playerAddress) .. "-" .. tostring(gamePlayId)] = {
    player = playerAddress,
    startTime = os.time(),
    status = "playing"
  }

  return {
    gamePlayId = gamePlayId,
    isNewUser = isNewUser,
    balance = tostring(balance)
  }
end

UserActions.EndGame = function(msg)
  assert(States.adminTable[msg.From], "Caller is not whitelisted")

  local gamePlayId = msg.Tags.gamePlayId
  local playerAddress = msg.Tags.playerAddress
  local score = msg.Tags.score or '0'
  assert(type(gamePlayId) == 'string', "gamePlayId is required!")
  assert(type(playerAddress) == 'string', "playerAddress is required!")

  local fullGamePlayId = tostring(playerAddress) .. "-" .. gamePlayId

  -- Verify the game exists and the provided playerAddress matches the game's player
  local gamePlay = States.gamePlays[fullGamePlayId]
  assert(gamePlay, "Game not found")
  assert(gamePlay.player == playerAddress, "Provided playerAddress does not match the game's player")

  -- Calculate score or determine rewards here
  -- This is a placeholder calculation, adjust as needed
  local playTime = os.time() - gamePlay.startTime
  -- local reward = math.floor(playTime / 60) -- 1 token per minute, for example

  -- Mint rewards to the player
  States.balances[playerAddress] = tostring(bint(States.balances[playerAddress] or '0') + bint(tostring(score)))
  States.totalSupply = tostring(bint(States.totalSupply) + bint(tostring(score)))

  -- Clean up the game data
  gamePlay.status = "ended"
  gamePlay.score = score
  States.gamePlays[fullGamePlayId] = gamePlay

  States.userTotalScore[playerAddress] = tostring(bint(States.userTotalScore[playerAddress] or '0') + bint(score))

  -- Update leaderboard
  Methods.updateLeaderboard(playerAddress, States.userTotalScore[playerAddress])

  return {
    reward = tostring(reward),
    player = playerAddress
  }
end

UserActions.setAdmin = function(msg)
  assert(Helper.isOwner(msg), "Only the contract owner can manage the whitelist")

  local address = msg.Tags.address
  local operation = msg.Tags.operation
  print('setAdmin', address, operation)
  assert(type(address) == 'string', "Address is required")
  assert(operation == 'add' or operation == 'remove', "Operation must be 'add' or 'remove'")

  if operation == 'add' then
    States.adminTable[address] = true
  else
    States.adminTable[address] = nil
  end

  return States.adminTable
end

UserActions.setNickname = function(msg)
  local nickname = msg.Tags.Nickname
  assert(type(nickname) == 'string', "Nickname must be a string")
  assert(#nickname >= 3 and #nickname <= 20, "Nickname must be between 3 and 20 characters")

  States.nicknames[msg.From] = nickname

  -- Update leaderboard if the player is already on it
  for _, entry in ipairs(States.leaderboard) do
    if entry.address == msg.From then
      Methods.updateLeaderboard(msg.From, entry.score)
      break
    end
  end

  return {
    success = true,
    message = "Nickname set successfully",
    nickname = nickname
  }
end

UserActions.GetLeaderboard = function()
  local leaderboardWithNicknames = {}
  for _, entry in ipairs(States.leaderboard) do
    table.insert(leaderboardWithNicknames, {
      address = entry.address,
      score = entry.score,
      nickname = States.nicknames[entry.address] or entry.address
    })
  end
  return leaderboardWithNicknames
end

UserActions.GetUserInfo = function(msg)
  local address = msg.Tags.Address
  local nickname = States.nicknames[address] or ""
  local balance = States.balances[address] or "0"
  return {
    nickname = nickname,
    balance = balance
  }
end

UserActions.SubmitAirdrop = function(msg)
  assert(Helper.isOwner(msg), "Only the contract owner can submit the airdrop")
  local address = msg.Tags.address
  local amount = msg.Tags.amount
  local balance = States.balances[address] or "0"
  States.balances[address] = tostring(bint(balance) + bint(amount))
  States.totalSupply = tostring(bint(States.totalSupply) + bint(amount))
  return {
    address = address,
    amount = amount,
    oldBalance = balance,
    newBalance = States.balances[address]
  }
end

UserActions.getInviteCodePrice = function()
  return Methods.getInviteCodePrice()
end

UserActions.buyInviteCode = function(msg)
  local user = msg.From
  local amount = bint(msg.amount or '0')
  local balance = bint(States.balances[user] or '0')
  local inviteCodePrice = bint(Methods.getInviteCodePrice())
  local totalAmount = inviteCodePrice * amount
  if (totalAmount <= bint('0')) then
    return {
      error = "Amount must be greater than 0"
    }
  end

  local currentCodeCount = bint(States.inviteCodePaidCount[user] or '0')
  if (balance < totalAmount) then
    return {
      error = "Insufficient SNK balance. You need at least 100 SNK to buy an invite code."
    }
  end

  States.balances[user] = tostring(balance - totalAmount)
  States.inviteCodeBalance = tostring(bint(States.inviteCodeBalance or '0') + totalAmount)
  States.inviteCodePaidCount[user] = tostring(currentCodeCount + amount)

  return {
    success = true,
    message = "Invite code bought successfully",
    inviteCodePaidCount = States.inviteCodePaidCount[user]
  }
end

UserActions.getInviteCodeCount = function(msg)
  local user = msg.user
  local inviteCodePaidCount = States.inviteCodePaidCount[user] or '0'
  print(msg.Tags, inviteCodePaidCount, user)
  return inviteCodePaidCount
end

-- the ContractActions, which can be called by other contracts via the `Send` function with "Event" param
ContractActions = ContractActions or {}

ContractActions.buy = function(msg)
  local payment = msg.From
  if States.paymentList[payment] ~= true then
    return {
      error = "payment not in list"
    }
  end

  local from = msg.Tags.from
  if type(from) ~= 'string' then
    return {
      error = "from is required!"
    }
  end

  local to = msg.Tags.to
  if type(to) ~= 'string' then
    return {
      error = "to is required!"
    }
  end
  if to ~= ao.id then
    return {
      error = "to must be the contract address"
    }
  end

  local amount = msg.Tags.amount
  if type(amount) ~= 'string' then
    Helper.log('snake:buy', msg, { amount = amount })
    return {
      error = "amount is required!"
    }
  end

  amount = bint(amount)
  if bint('0') >= amount then
    Helper.log('snake:buy', msg, { amount = amount, zero = bint('0'), result = bint('0') < amount })
    return {
      error = "amount must be greater than 0"
    }
  end

  Methods.updateBalance(from, 'mint', amount)
  return true
end

-- UserActions.buy = ContractActions.buy

Handlers.add(
  "router",
  function(msg)
    Helper.log('snake:router', msg, {
      From = msg.From,
      UserAction = msg.UserAction,
      ContractAction = msg.ContractAction,
      Tags = msg.Tags
    })
    local noUserAction = msg.UserAction == nil or UserActions[msg.UserAction] == nil
    local noContractAction = msg.ContractAction == nil or ContractActions[msg.ContractAction] == nil

    if (noUserAction and noContractAction) then return false end
    return true
  end,
  function(msg)
    local Data = nil

    if (msg.UserAction and UserActions[msg.UserAction]) then
      Data = UserActions[msg.UserAction](msg)
    elseif (msg.ContractAction and ContractActions[msg.ContractAction]) then
      Data = ContractActions[msg.ContractAction](msg)
    end
    if (Data == nil) then
      Data = ''
    end
    if (type(Data) ~= "table") then
      Data = {
        value = tostring(Data)
      }
    end

    msg.reply({
      Data = Data,
    })
  end
)

-- return {
--   Info = Info,
--   States = States,
--   Methods = Methods,
--   UserActions = UserActions,
--   ContractActions = ContractActions,
-- }
