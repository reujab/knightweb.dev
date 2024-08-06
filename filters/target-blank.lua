-- This filter opens external links in new tabs.
function Link(el)
	if el.target:match("^http") then
		el.attributes["target"] = "_blank"
	end
	return el
end
