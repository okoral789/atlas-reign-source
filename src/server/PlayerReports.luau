--!strict
-- Atlas Reign, 2026-10-31. Reports are evidence for review, never an automatic punishment.
local Reports = {}
Reports.__index = Reports
Reports.REASONS = { teaming = true, exploiting = true, harassment = true }
function Reports.new(store: any, deps: any)
	return setmetatable({ store=store, deps=deps, requests={}, busy={}, last={} }, Reports)
end
function Reports.submit(self: any, author: any, target: any, reason: any): any
	if type(target)~="number" or target%1~=0 or target<=0 or target==author.UserId or not Reports.REASONS[reason] then
		return {ok=false,message="Choose another player and a report reason."}
	end
	local context = self.deps.context(author,target)
	if context==nil then return {ok=false,message="Report a player participating in your current match."} end
	if reason=="teaming" and context.mode~="ffa" then return {ok=false,message="Teaming reports apply to free-for-all matches."} end
	local key=context.match_id..":"..author.UserId..":"..target..":"..reason
	local previous=self.requests[key]
	if previous and previous.saved then return {ok=true,id=previous.id,message="Report already received."} end
	local now=self.deps.now()
	if self.busy[author.UserId] or (self.last[author.UserId] and now-self.last[author.UserId]<30) then
		return {ok=false,message="Wait 30 seconds before sending another report."}
	end
	local request=previous or {id=self.deps.id()}
	self.requests[key]=request; self.busy[author.UserId]=true
	local record={id=request.id,reporter=author.UserId,target=target,reason=reason,status="pending",created=now,context=context}
	local ok=pcall(function()
		self.store:UpdateAsync("r_"..request.id,function(old) return old or record end)
		self.store:UpdateAsync("recent",function(old)
			local rows=if type(old)=="table" then table.clone(old) else {}
			for _,row in rows do if row.id==request.id then return nil end end
			table.insert(rows,1,record)
			-- shortcut: show 200 recent reports; each full record remains separately stored for an archive.
			while #rows>200 do table.remove(rows) end
			return rows
		end)
	end)
	self.busy[author.UserId]=nil
	if not ok then return {ok=false,message="Report could not be saved. Please retry."} end
	request.saved=true; self.last[author.UserId]=now
	return {ok=true,id=request.id,message="Report saved for review. Reports do not cause automatic bans."}
end
function Reports.inbox(self: any): any
	local ok,rows=pcall(self.store.GetAsync,self.store,"recent")
	return {ok=ok,rows=if ok and type(rows)=="table" then rows else {}}
end
function Reports.review(self: any, id: any): any
	if type(id)~="string" or #id>40 or not string.match(id,"^[%w%-]+$") then return {ok=false} end
	local ok=pcall(function()
		self.store:UpdateAsync("r_"..id,function(old)
			if type(old)~="table" then return nil end
			local row=table.clone(old);row.status="reviewed";return row
		end)
		self.store:UpdateAsync("recent",function(old)
			if type(old)~="table" then return nil end
			local rows={}
			for _,row in old do
				local copy=table.clone(row);if row.id==id then copy.status="reviewed" end
				table.insert(rows,copy)
			end
			return rows
		end)
	end)
	return {ok=ok}
end
return Reports
