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

-- there data here should be const after deploy
Info = Info or {
  version = "1.0.0",
  name = "BSTSwap",
  symbol = "BSTSwap",
  decimals = 18
}

-- Add this constant at the top of the file, after the Info table

-- the contract's states
InitStates = function()
  return {
    totalSupply = 0,
    balances = {},
    allowances = {},
    deposits = {},
    withdraws = {}
  }
end

States = States or InitStates()

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

Methods.reset = function()
  States = InitStates()
end

Methods.allowance = function(owner, spender)
  return States.allowances[owner][spender] or '0'
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

  return States.balances[account]
end

UserActions.transfer = function(msg)
  local from = msg.From
  local to = msg.Tags.to
  local amount = msg.Tags.amount
  assert(type(to) == 'string', "to is required!")
  assert(type(amount) == 'string', "amount is required!")

  amount = bint(amount)
  assert(bint('0') < amount, 'amount must be greater than 0')

  local balance = bint(States.balances[from])
  assert(balance >= amount, "insufficient balance")

  States.balances[from] = tostring(balance - amount)
  States.balances[to] = tostring(bint(States.balances[to] or '0') + amount)

  local appAddress = msg.appAddress
  local appAction = msg.appAction
  if (appAddress and appAction) then
    ao.send({
      Target = appAddress,
      Tags = {
        ContractAction = appAction,
        from = from,
        to = to,
        amount = msg.amount
      }
    })
  end
  return {
    success = true,
    newBalanceForFrom = States.balances[from],
    newBalanceForTo = States.balances[to]
  }
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
  }
end

UserActions.adminDeposit = function(msg)
  assert(Helper.isOwner(msg), "Permission deny, only the contract owner can call")

  local to = msg.Tags.to
  local amount = msg.Tags.amount
  local network = msg.Tags.network
  local hash = msg.Tags.hash
  assert(type(to) == 'string', "to is required")
  assert(type(amount) == 'string', "amount is required")
  assert(type(network) == 'string', "network is required")
  assert(type(hash) == 'string', "hash is required")

  States.deposits[network] = States.deposits[network] or {}
  assert(not States.deposits[network][hash], "deposit with hash " .. hash .. " already exists")

  States.deposits[network][hash] = {
    to = to,
    amount = amount
  }
  local oldBalance = bint(States.balances[to] or '0')
  States.balances[to] = tostring(oldBalance + bint(amount))
  local oldTotalSupply = bint(States.totalSupply)
  States.totalSupply = tostring(oldTotalSupply + bint(amount))

  return {
    oldBalance = oldBalance,
    newBalance = States.balances[to],
    amount = amount,
    oldTotalSupply = oldTotalSupply,
    totalSupply = States.totalSupply
  }
end

UserActions.withdrawStart = function(msg)
  local from = msg.From
  local id = msg.Data.id
  local amount = msg.Data.amount
  local network = msg.Data.network
  local to = msg.Data.to

  assert(type(from) == 'string', "from is required")
  assert(type(amount) == 'string', "amount is required")
  assert(type(network) == 'string', "network is required")
  assert(type(to) == 'string', "to is required")

  local balance = bint(States.balances[from])
  assert(balance >= bint(amount), "insufficient balance")

  States.balances[from] = tostring(balance - bint(amount))
  States.totalSupply = tostring(bint(States.totalSupply) - bint(amount))

  States.withdraws[network][id] = {
    from = from,
    amount = amount,
    to = to,
    status = "pending",
    hash = ""
  }
  return States.balances[from]
end

UserActions.withdrawDone = function(msg)
  assert(Helper.isOwner(msg), "Permission deny, only the contract owner can call")

  local id = msg.Data.id
  local amount = msg.Data.amount
  local network = msg.Data.network
  local from = msg.Data.from
  local to = msg.Data.to
  local hash = msg.Data.hash

  assert(type(id) == 'string', "id is required")
  assert(type(from) == 'string', "from is required")
  assert(type(amount) == 'string', "amount is required")
  assert(type(network) == 'string', "network is required")
  assert(type(to) == 'string', "to is required")
  assert(type(hash) == 'string', "hash is required")

  local withdrawItem = States.withdraws[network][id]
  assert(withdrawItem, "withdraw item not found")
  assert(withdrawItem.status == "pending", "withdraw item status is not pending")
  assert(withdrawItem.from == from, "from is not match")
  assert(withdrawItem.amount == amount, "amount is not match")
  assert(withdrawItem.to == to, "to is not match")
  assert(withdrawItem.hash == "", "hash is not empty")

  States.withdraws[network][id].hash = hash
  States.withdraws[network][id].status = "done"

  return States.withdraws[network][id]
end

ContractActions = ContractActions or {}

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

return {
  Info = Info,
  States = States,
  Methods = Methods,
  UserActions = UserActions,
  ContractActions = ContractActions
}
