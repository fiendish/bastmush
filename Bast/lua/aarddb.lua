-- $Id$
require 'tprint'
require 'verify'
require 'pluginhelper'
require 'sqlitedb'
require 'aardutils'

Aarddb = Sqlitedb:subclass()

function Aarddb:initialize(args)
  super(self, args)   -- notice call to superclass's constructor
  self.dbname = "/aardinfo.db"
  self.version = 2
  self.versionfuncs[2] = self.resetplanestable

  self:addtable('planespools',[[CREATE TABLE planespools(
      pool_id INTEGER NOT NULL PRIMARY KEY autoincrement,
      poollayer TEXT NOT NULL,
      poolnum INT NOT NULL
        )]], nil, self.createplanespoolstable, 'pool_id')

  self:addtable('planesmobs', [[CREATE TABLE planesmobs(
      mob_id INTEGER NOT NULL PRIMARY KEY autoincrement,
      mobname TEXT NOT NULL,
      poolnum INT NOT NULL
        )]], nil, self.createplanesmobstable, 'mob_id')


  self:addtable('areas', [[CREATE TABLE areas(
      area_id INTEGER NOT NULL PRIMARY KEY autoincrement,
      keyword TEXT UNIQUE NOT NULL,
      name TEXT UNIQUE NOT NULL,
      afrom INT default 1,
      ato INT default 1,
      alock INT default 0,
      builder TEXT,
      speedwalk TEXT
        )]], nil, nil, 'area_id')

  self:addtable('helplookup', [[CREATE TABLE helplookup(
      lookup_id INTEGER NOT NULL PRIMARY KEY autoincrement,
      lookup TEXT UNIQUE NOT NULL,
      topic TEXT
        )]], nil, nil, 'lookup_id')

  self:addtable('helps', [[CREATE TABLE helps(
      help_id INTEGER NOT NULL PRIMARY KEY autoincrement,
      keyword TEXT UNIQUE NOT NULL,
      helptext TEXT,
      added INT
        )]], nil, nil, 'help_id')

  self:addtable('notes', [[CREATE TABLE notes(
      note_id INTEGER NOT NULL PRIMARY KEY autoincrement,
      area TEXT NOT NULL,
      room INT default -1,
      keywords TEXT NOT NULL,
      note TEXT NOT NULL
        )]], nil, nil, 'note_id')

  self:postinit() -- this is defined in sqlitedb.lua, it checks for upgrades and creates all tables
end

function Aarddb:addnote(note)
  if self:open('addnote') then
    local stmt = self.db:prepare(self:converttoinsert('notes'))
    stmt:bind_names( note )
    stmt:step()
    local retval = stmt:finalize()
    local rowid = self.db:last_insert_rowid()
    phelper:mdebug('added note', rowid)
    self:close('addnote')
    return rowid
  end
end

function Aarddb:removenote(notenum)
  timer_start('Aarddb:removenote')
  --tprint(item)
  local tchanges = 0
  if self:open('removenote') then
    tchanges = self.db:total_changes()
    self.db:exec("DELETE FROM notes WHERE note_id= " .. tostring(notenum))
    tchanges = self.db:total_changes() - tchanges
    self:close('removenote')
  end
  timer_end('Aarddb:removenote')
  return tchanges
end

function Aarddb:getallnotes()
  local results = {}
  local sqlcmd = 'SELECT * FROM notes'
  if self:open('getallnotes') then
    local stmt = self.db:prepare(sqlcmd)
    if not stmt then
      phelper:plugin_header('Note Lookup')
      print('Get All Notes: The lookup arguments do not create a valid sql statement to get notes')
    else
      for a in stmt:nrows() do
        table.insert(results, a)
      end
    end
    self:close('getallnotes')
  end
  return results
end

function Aarddb:lookupnotes(notestr)
  local results = {}
  local sqlcmd = 'SELECT * FROM notes WHERE ' .. notestr
  if self:open('lookupnotes') then
    local stmt = self.db:prepare(sqlcmd)
    if not stmt then
      phelper:plugin_header('Note Lookup')
      print('The lookup arguments do not create a valid sql statement to get notes')
    else
      for a in stmt:nrows() do
        table.insert(results, a)
      end
    end
    self:close('lookupnotes')
  end
  return results
end

function Aarddb:resetplanestable()
  if self:open() then
    self.db:exec([[DROP TABLE IF EXISTS planespools;]])
    self.db:exec([[DROP TABLE IF EXISTS planesmobs;]])
    self:checktable('planespools')
    self:checktable('planesmobs')
  end
end

function Aarddb:createplanespoolstable()
  if self:open() then
    self.db:exec([[BEGIN TRANSACTION;]])
    local stmt = self.db:prepare(self:converttoinsert('planespools'))
    for _,item in pairs(planespools) do
      stmt:bind_names(  item  )
      stmt:step()
      stmt:reset()
    end
    stmt:finalize()
    self.db:exec([[COMMIT;]])
    self:close()
  end
end

function Aarddb:createplanesmobstable()
  if self:open() then
    self.db:exec([[BEGIN TRANSACTION;]])
    local stmt = self.db:prepare(self:converttoinsert('planesmobs'))
    for _,item in pairs(planesmobs) do
      stmt:bind_names(  item  )
      stmt:step()
      stmt:reset()
    end
    stmt:finalize()
    self.db:exec([[COMMIT;]])
    self:close()
  end

end

function Aarddb:planeslookup(mob)
  local tmobs = {}
  if self:open() then
    for a in self.db:nrows( "SELECT DISTINCT(planesmobs.mobname), planespools.poollayer, planespools.poolnum FROM planesmobs, planespools  WHERE planesmobs.mobname LIKE '%" .. mob .. "%' and planesmobs.poolnum == planespools.poolnum" ) do
      table.insert(tmobs, a)
    end
    self:close()
  end
  return tmobs
end

function Aarddb:getallareas()
  local areasbykeyword = {}
  if self:open() then
    for a in self.db:nrows( "SELECT * FROM areas" ) do
      areasbykeyword[a.keyword] = a
    end
    self:close()
  end
  return areasbykeyword
end

function Aarddb:getallareasbyname()
  local areas = {}
  if self:open() then
    for a in self.db:nrows( "SELECT * FROM areas" ) do
      areas[a.name] = a
    end
    self:close()
  end
  return areas
end


function Aarddb:lookupareas(areastr)
  local results = {}
  local sqlcmd = 'SELECT * FROM areas WHERE ' .. areastr
  if self:open('lookupareas') then
    local stmt = self.db:prepare(sqlcmd)
    if not stmt then
      phelper:plugin_header('Area Lookup')
      print('The lookup arguments do not create a valid sql statement to get areas')
    else
      for a in stmt:nrows() do
        table.insert(results, a)
      end
    end
    self:close('lookupareas')
  end
  return results
end

function Aarddb:lookupareasbyname(area)
  local areas = {}
  local area = fixsql(area, true)
  if self:open() and self:checktable('areas')  then
    for a in self.db:nrows( "SELECT * FROM areas WHERE name LIKE " .. area ) do
      table.insert(areas, a)
    end
    self:close()
  end
  return areas
end

function Aarddb:lookupareasbyexactname(area)
  local areas = {}
  local area = fixsql(area)
  if self:open() and self:checktable('areas')  then
    for a in self.db:nrows( "SELECT * FROM areas WHERE LOWER(name) = LOWER(" .. area ..  ")") do
      table.insert(areas, a)
    end
    self:close()
  end
  return areas
end

function Aarddb:lookupareasbykeyword(keyword)
  local areas = {}
  local keyword = fixsql(keyword, true)
  if self:open() and self:checktable('areas')  then
    for a in self.db:nrows( "SELECT * FROM areas WHERE keyword LIKE " .. keyword ) do
      table.insert(areas, a)
    end
    self:close()
  end
  return areas
end

function Aarddb:lookupareasbylevel(level)
  local areas = {}
  if self:open() then
    for a in self.db:nrows( "SELECT * FROM areas WHERE afrom < " .. level .. " and ato > " .. level .. ";" ) do
      table.insert(areas, a)
    end
    self:close()
  end
  return areas
end

function Aarddb:addareas(area_list)
  if self:open() then
    local allareas = self:getallareas()

    assert (self.db:exec("BEGIN TRANSACTION"))
    local stmt = self.db:prepare(self:converttoinsert('areas'))
    local stmtupd = self.db:prepare(self:converttoupdate('areas', 'keyword'))

    for i,v in pairs(area_list) do
      if v.keyword ~= nil and allareas[v.keyword] == nil then
        stmt:bind_names (v)
        stmt:step()
        stmt:reset()
      elseif v.keyword ~= nil then
        stmtupd:bind_names(v)
        stmtupd:step()
        stmtupd:reset()
      end
    end
    stmt:finalize()
    stmtupd:finalize()
    assert (self.db:exec("COMMIT"))
    self:close()
  end
end

function Aarddb:updatebuilders(area_list)
  if self:open() then
    assert (self.db:exec("BEGIN TRANSACTION"))
    local stmt = self.db:prepare[['update areas set author=:author where keyword=:keyword;']]
    for i,v in ipairs(area_list) do
      stmt:bind_names (v)
      stmt:step()
      stmt:reset()
    end
    stmt:finalize()
    assert (self.db:exec("COMMIT"))
    self:close()
  end
end

function Aarddb:updatespeedwalks(area_list)
  if self:open() then
    assert (self.db:exec("BEGIN TRANSACTION"))
    local stmt = self.db:prepare[['update areas set speedwalk=:speedwalk where keyword=:keyword;']]
    for i,v in ipairs(area_list) do
      stmt:bind_names (v)
      stmt:step()
      stmt:reset()
    end
    stmt:finalize()
    assert (self.db:exec("COMMIT"))
    self:close()
  end
end


function Aarddb:addhelplookup(lookup)
  if self:open() then
    local stmt = self.db:prepare(self:converttoinsert('helplookup'))
    stmt:bind_names(  lookup  )
    stmt:step()
    stmt:finalize()
    local rowid = self.db:last_insert_rowid()
    phelper:mdebug("inserted helplookup :", rowid)
    self:close()
    return rowid
  end
  return nil
end


function Aarddb:addhelp(help)
  if self:open() then
    help.helptext = serialize.save("thelptext", help.helptext)
    local hashelp = self:hashelp(help.keyword)
    local message = 'inserted help:'
    local stmt
    if hashelp then
      stmt = self.db:prepare[[ UPDATE helps SET helptext=:helptext, added=:added WHERE keyword=:keyword ]]
      message = 'updated help:'
    else
      stmt = self.db:prepare[[ INSERT INTO helps VALUES (NULL, :keyword,
                                                            :helptext, :added) ]]
    end
    stmt:bind_names(  help  )
    stmt:step()
    stmt:finalize()
    local rowid = self.db:last_insert_rowid()
    phelper:mdebug(message, rowid)
    self:close()
    return rowid
  end
end

function Aarddb:hashelp(keyword)
  local thelp = nil
  if self:open() then
    for a in self.db:nrows('SELECT * FROM helps WHERE keyword = "' .. keyword .. '"' ) do
      if a['keyword'] == keyword then
        self:close()
        return true
      end
    end
    self:close()
  end
  return false
end

function Aarddb:gethelp(thelp)
  local help = {}
  if self:open() then
    for a in self.db:nrows('SELECT * FROM helplookup where lookup == "' .. thelp ..'"') do
      table.insert(help, a['topic'])
    end
    self:close()
  end
  if #help > 1 or #help == 0 then
    return false
  else
    if self:open() then
      local thelp = {}
      for a in self.db:nrows('SELECT * FROM helps where keyword == "' .. help[1] ..'"') do
        thelp = a
        loadstring (a.helptext) ()
        thelp.helptext = thelptext
      end
      self:close()
      return thelp
    end
  end
  return false

end

function Aarddb:clearhelptable()
  if self:open() then
    self.db:exec([[DROP TABLE IF EXISTS helplookup;]])
    self:close(true)
  end
  if self:open() then
    self.db:exec([[DROP TABLE IF EXISTS helps;]])
    self:close(true)
  end
  self:checktable('helps')
  self:checktable('helplookup')
end

planespools = {
  {poolname = 'Gladsheim', poolnum = 1},
  {poolname = 'Pandemonium', poolnum = 2},
  {poolname = 'Hades', poolnum = 3},
  {poolname = 'Gehenna', poolnum = 4},
  {poolname = 'Acheron', poolnum = 5},
  {poolname = 'Twin Paradises', poolnum = 6},
  {poolname = 'Arcadia', poolnum = 7},
  {poolname = 'Seven Heavens', poolnum = 8},
  {poolname = 'Elysium', poolnum = 10},
  {poolname = 'Beastlands', poolnum = 11},
}

planesmobs = {
  {name='A paladin einheriar', pool=1},
  {name='A psionic einheriar', pool=1},
  {name='A cleric einheriar', pool=1},
  {name='A ranger einheriar', pool=1},
  {name='A warrior einheriar', pool=1},
  {name='A thief einheriar', pool=1},
  {name='A mage einheriar', pool=1},
  {name='A titan', pool=1},
  {name='A per', pool=1},
  {name='A bariaur', pool=1},
  {name='A malelephant', pool=2},
  {name='A nightmare', pool=2},
  {name='A larva', pool=2},
  {name='A hordling', pool=3},
  {name='A yagnoloth', pool=3},
  {name='A night hag', pool=3},
  {name='An ultroloth', pool=4},
  {name='An arcanaloth', pool=4},
  {name='A dergholoth', pool=4},
  {name='A hydroloth', pool=4},
  {name='A mezzoloth', pool=4},
  {name='A psicloth', pool=4},
  {name='A nycaloth', pool=4},
  {name='A vaporighu', pool=4},
  {name='General of Gehenna', pool=4},
  {name='An ultroloth', pool=5},
  {name='A dergholoth', pool=5},
  {name='A hydroloth', pool=5},
  {name='A mezzoloth', pool=5},
  {name='A psicloth', pool=5},
  {name='A nycaloth', pool=5},
  {name='An adamantite dragon', pool=6},
  {name='An air sentinel', pool=6},
  {name='A monadic deva', pool=6},
  {name='An agathinon aasimon', pool=7},
  {name='An astral deva', pool=7},
  {name='A translator', pool=7},
  {name="A t'uen-rin", pool=7},
  {name='A lantern archon', pool=8},
  {name='A tome archon', pool=8},
  {name='A noctral', pool=8},
  {name='A planetar aasimon', pool=8},
  {name='A warden archon', pool=8},
  {name='A hound archon', pool=8},
  {name='A sword archon', pool=8},
  {name='A zoveri', pool=8},
  {name='A light aasimon', pool=10},
  {name='A solar aasimon', pool=10},
  {name='A movanic deva', pool=10},
  {name='A balanea', pool=10},
  {name='A phoenix', pool=10},
  {name='A moon dog', pool=10},
  {name='A mortai', pool=11},
  {name='An animal spirit', pool=11},
  {name='An animal lord', pool=11},
  {name='A warden beast', pool=11},
}
