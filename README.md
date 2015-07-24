# RecountChatFilter
A tiny little addon for World of Warcraft that reduces Recount/Skada spam to clickable one-liners.

I got tired of people spamming their damage/healing meters from Recount/Skada in my chat frame, so to I wrote this addon. It works by listening for the Recount/Skada "headlines", and then for the next short period of time, it captures and filters out all of the datalines. The "headline" is turned into a clickable link, which displays a tooltip with the datalines in it when clicked.

## Screenshots

Damage report from Recount. When RecountChatFilter has access to the players' class information, it will use this information to color the data lines according to the players' classes.

![Class colors](http://garbagemule.github.io/RecountChatFilter/img/recount_class_colors.jpg)

The same damage report from Recount, but with the fallback data line colors when no class information is available.

![Fallback colors](http://garbagemule.github.io/RecountChatFilter/img/recount_normal.jpg)
