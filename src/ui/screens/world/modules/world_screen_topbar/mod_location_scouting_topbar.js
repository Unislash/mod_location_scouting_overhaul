// -------------------------------------------------------------------------
// mod_location_scouting_topbar.js
// -------------------------------------------------------------------------

"use strict";

(function ()
{
    var mLsFilterBtn      = null;
    var mLsLegendaryBtn = null;
    var mLsCampBtn      = null;
    var mLsResetBtn     = null;
    var mLsWrapper      = null;
    var mLsTooltip      = null;

    function createTooltip()
    {
        mLsTooltip = $('<div class="mod-ls-tooltip"/>');
        $("body").append(mLsTooltip);
    }

    function attachTooltip(_el, _text)
    {
        _el.on("mouseenter", function (e)
        {
            mLsTooltip.html(_text).addClass("mod-ls-tooltip-visible");
        });
        _el.on("mousemove", function (e)
        {
            mLsTooltip.css({ left: e.clientX + 12, top: e.clientY + 20 });
        });
        _el.on("mouseleave", function ()
        {
            mLsTooltip.removeClass("mod-ls-tooltip-visible");
        });
    }

    function applyButtonState(_mode)
    {
        if (!mLsLegendaryBtn) return;

        // asyncCall passes args as an array - unwrap if needed
        if (Array.isArray(_mode)) _mode = _mode[0];

        if (_mode === "legendary")
            mLsLegendaryBtn.addClass("mod-ls-btn-active");
        else
            mLsLegendaryBtn.removeClass("mod-ls-btn-active");

        if (_mode === "camp")
            mLsCampBtn.addClass("mod-ls-btn-active");
        else
            mLsCampBtn.removeClass("mod-ls-btn-active");

        if (_mode === "filter")
            mLsFilterBtn.addClass("mod-ls-btn-active");
        else
            mLsFilterBtn.removeClass("mod-ls-btn-active");
    }

    function applyUISettings(_args)
    {
        if (!mLsWrapper) return;

        // asyncCall passes args as an array
        var pos     = Array.isArray(_args) ? _args[0] : _args;
        var compact = Array.isArray(_args) ? _args[1] : false;

        // Smart positioning: on screens narrower than 1920, nudge buttons
        // left automatically (only when user hasn't changed from default 72)
        if (pos === 72)
        {
            var sw = window.innerWidth || document.documentElement.clientWidth || 1920;
            if (sw < 1920)
                pos = 72 - Math.round((1920 - sw) / 100);
        }

        // Setting is "percent from left", CSS uses "right"
        mLsWrapper.css("right", (100 - pos) + "%");

        if (compact)
        {
            mLsLegendaryBtn.find(".mod-ls-label").text("L");
            mLsCampBtn.find(".mod-ls-label").text("C");
        }
        else
        {
            mLsLegendaryBtn.find(".mod-ls-label").text("Legends");
            mLsCampBtn.find(".mod-ls-label").text("Camps");
        }
    }

    var _originalRegisterModules = WorldScreen.prototype.registerModules;
    WorldScreen.prototype.registerModules = function ()
    {
        _originalRegisterModules.call(this);
        this._lsCreateButtons();
        createTooltip();

        // Must be own property on the instance - asyncCall does target[methodName](_args)
        // and target is the instance, not the prototype
        this.setScoutingButtonState = function (_mode)
        {
            applyButtonState(_mode);
        };

        this.applyScoutingUISettings = function (_args)
        {
            applyUISettings(_args);
        };
    };

    var _originalUnregisterModules = WorldScreen.prototype.unregisterModules;
    WorldScreen.prototype.unregisterModules = function ()
    {
        _originalUnregisterModules.call(this);
        if (mLsWrapper)
        {
            mLsWrapper.remove();
            mLsWrapper      = null;
            mLsFilterBtn      = null;
            mLsLegendaryBtn = null;
            mLsCampBtn      = null;
            mLsResetBtn     = null;
        }
        if (mLsTooltip)
        {
            mLsTooltip.remove();
            mLsTooltip = null;
        }
    };

    WorldScreen.prototype._lsCreateButtons = function ()
    {
        var self = this;

        mLsWrapper = $('<div class="mod-ls-wrapper"/>');
        self.mTopBarContainer.append(mLsWrapper);

        mLsFilterBtn = $(
            '<div class="ui-control mod-ls-btn mod-ls-btn-filter">' +
                '<span class="mod-ls-icon mod-ls-icon-filter"></span>' +
            '</div>'
        );

        mLsLegendaryBtn = $(
            '<div class="ui-control mod-ls-btn">' +
                '<span class="mod-ls-label">Legends</span>' +
            '</div>'
        );

        mLsCampBtn = $(
            '<div class="ui-control mod-ls-btn">' +
                '<span class="mod-ls-label">Camps</span>' +
            '</div>'
        );

        mLsResetBtn = $(
            '<div class="ui-control mod-ls-btn mod-ls-btn-reset">' +
                '<span class="mod-ls-icon mod-ls-icon-reset"></span>' +
            '</div>'
        );

        mLsWrapper.append(mLsFilterBtn);
        mLsWrapper.append(mLsLegendaryBtn);
        mLsWrapper.append(mLsCampBtn);
        mLsWrapper.append(mLsResetBtn);

        attachTooltip(mLsFilterBtn,    "Filter (Ctrl+F):<br>- Black tiles can contain a Legendary Location you filtered<br>- See \"Escape => Mod Options => Location Scouting => Filter\"<br>- Tick or Untick Legendary Locations in the Filter Page<br>- Move closer to reveal whether they contain one");
        attachTooltip(mLsLegendaryBtn, "Legendary Scouting (Ctrl+L):<br>- Scout for all Legendary Locations without any Filter<br>- Black tiles can contain a Legendary Location<br>- Move closer to reveal whether they contain one");
        attachTooltip(mLsCampBtn,      "Camp Scouting (Ctrl+E):<br>- Black tiles can contain an Enemy Camp<br>- Move closer to reveal whether they contain one");
        attachTooltip(mLsResetBtn,     "Refresh Scouting:<br>- Resets Camp Scouting (camps can respawn)<br>- Fixes overlay gaps caused by battles<br>- Does NOT reset Legendary Scouting progress");

        mLsFilterBtn.on("click", function ()
        {
            SQ.call(self.mSQHandle, "onScoutingButtonClicked", "filter");
        });

        mLsLegendaryBtn.on("click", function ()
        {
            SQ.call(self.mSQHandle, "onScoutingButtonClicked", "legendary");
        });

        mLsCampBtn.on("click", function ()
        {
            SQ.call(self.mSQHandle, "onScoutingButtonClicked", "camp");
        });

        mLsResetBtn.on("click", function ()
        {
            SQ.call(self.mSQHandle, "onResetCampScoutingClicked");
        });
    };
})();
