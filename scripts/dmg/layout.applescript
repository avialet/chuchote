-- Disposition de la fenetre du DMG, reglee par le Finder sur un volume de travail monte.
-- Usage (par scripts/make-dmg.sh --layout) : osascript layout.applescript <volume> <App.app>
-- Fenetre 660x400 pt en vue icones, icones de 128, l'app en (160,190), Applications en (500,190),
-- fond .background/fond.png. Le Finder ecrit le .DS_Store du volume, copie ensuite dans scripts/dmg/DS_Store.
on run argv
	set volumeName to item 1 of argv
	set appName to item 2 of argv
	-- Sans autorisation Automation, le Finder ne repond pas : erreur au bout de 30 s (et non 120).
	with timeout of 30 seconds
	tell application "Finder"
		tell disk volumeName
			open
			set current view of container window to icon view
			set toolbar visible of container window to false
			set statusbar visible of container window to false
			set the bounds of container window to {200, 120, 860, 520}
			set viewOptions to the icon view options of container window
			set arrangement of viewOptions to not arranged
			set icon size of viewOptions to 128
			set text size of viewOptions to 13
			set background picture of viewOptions to file ".background:fond.png"
			set position of item appName of container window to {160, 190}
			set position of item "Applications" of container window to {500, 190}
			close
			open
			update without registering applications
			delay 2
			close
		end tell
	end tell
	end timeout
end run
