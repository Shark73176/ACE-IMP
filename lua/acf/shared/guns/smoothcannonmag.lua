--define the class
ACF_defineGunClass("SBCM", {
	type = "Gun",
	spread = 0.095,
	name = "Smooth-Bore Cannon Magazine",
	desc = ACFTranslation.GunClasses[16],
	muzzleflash = "C",
	rofmod = 1,
	sound = "ace_weapons/multi_sound/120mm_multi.mp3",
	year = 2005,
    autosound = "acf_extra/tankfx/reload.wav",
	noloader = true,
} )

--add a gun to the class

ACF_defineGun("100mmSBCM", {
	name = "100mm Smoothbore Cannon M",
	desc = "100mm Smoothbore cannon, with good penetration performance, can perform a deadly strike in one single pass. Seen on those modern tank destroyers.",
	model = "models/tankgun_new/tankgun_100mm.mdl",
	sound = "ace_weapons/multi_sound/100mm_multi.mp3",
	gunclass = "SBCM",
	caliber = 10.0,
	weight = 1700,
	magsize = 3,
	magreload = 9,
	year = 1960,
	rofmod = 0.40,
	round = {
		maxlength = 93,
		propweight = 20
	}
} )

ACF_defineGun("120mmSBCM", {
	name = "120mm Smoothbore Cannon M",
	desc = "120mm Smoothbore cannon, powerful general purpose main battle tank cannon",
	model = "models/tankgun_new/tankgun_120mm.mdl",
	sound = "ace_weapons/multi_sound/120mm_multi.mp3",
	gunclass = "SBCM",
	caliber = 12.0,
	weight = 3200,
	magsize = 3,
	magreload = 11,
	year = 1970,
	rofmod = 0.283,
	round = {
		maxlength = 115,
		propweight = 30
	}
} )

ACF_defineGun("140mmSBCM", {
	name = "140mm Smoothbore Cannon M",
	desc = "140mm Smoothbore cannon, heavy railgun like cannon spawned out of a hatred of 60 tons. 'Your litterly removing the armor tool' -Anon",
	model = "models/tankgun_new/tankgun_140mm.mdl",
	sound = "ace_weapons/multi_sound/120mm_multi.mp3",
	gunclass = "SBCM",
	caliber = 14.0,
	weight = 4300,
	magsize = 3,
	magreload = 13,
	year = 1995,
	rofmod = 0.209,
	round = {
		maxlength = 140,
		propweight = 45
	}
} )


ACF_defineGun("170mmSBCM", {
	name = "170mm Smoothbore Cannon M",
	desc = "Some might laugh at those who choose to forego armor. The 170mm laughs at anyone as it casually tears all tanks alike to shreds.",
	model = "models/tankgun_new/tankgun_170mm.mdl",
	sound = "ace_weapons/multi_sound/120mm_multi.mp3",
	gunclass = "SBCM",
	caliber = 17.0,
	weight = 5400,
	magsize = 3,
	magreload = 15,
	year = 1990,
	rofmod = 0.1425,
	round = {
		maxlength = 180,
		propweight = 55
	}
} )

ACF_defineGun("200mmSBCM", {
	name = "200mm Smoothbore Cannon M",
	desc = "Something bigger than 170mm smoothbore cannon, also you can penetrate planet by this huge gun.(You should resize model by propresizer 2x!)",
	model = "models/tankgun_new/tankgun_100mm.mdl",
	sound = "ace_weapons/multi_sound/120mm_multi.mp3",
	gunclass = "SBCM",
	caliber = 20.0,
	weight = 6500 / 8,
	magsize = 3,
	magreload = 17,
	year = 2020,
	rofmod = 0.107,
	round = {
		maxlength = 210,
		propweight = 70
	}
} )


