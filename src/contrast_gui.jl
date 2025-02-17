function change_red(col::CLim{T}, chan::CLim{T2}) where {T<:AbstractRGB, T2<:GrayLike}
    cmin = T(chan.min, green(col.min), blue(col.min))
    cmax = T(chan.max, green(col.max), blue(col.max))
    return CLim(cmin, cmax)
end
function change_green(col::CLim{T}, chan::CLim{T2}) where {T<:AbstractRGB, T2<:GrayLike}
    cmin = T(red(col.min), chan.min, blue(col.min))
    cmax = T(red(col.max), chan.max, blue(col.max))
    return CLim(cmin, cmax)
end
function change_blue(col::CLim{T}, chan::CLim{T2}) where {T<:AbstractRGB, T2<:GrayLike}
    cmin = T(red(col.min), green(col.min), chan.min)
    cmax = T(red(col.max), green(col.max), chan.max)
    return CLim(cmin, cmax)
end
change_red(col::Observable, chan::CLim) = change_red(col[], chan)
change_green(col::Observable, chan::CLim) = change_green(col[], chan)
change_blue(col::Observable, chan::CLim) = change_blue(col[], chan)

change_channel(col::Observable, chanlim::CLim, i::Int) = change_channel(col[], chanlim, i)

function contrast_gui(enabled::Observable{Bool}, hists::Vector, clim::Observable{CLim{T}}) where {T<:AbstractRGB}
    @assert length(hists) == 3 #one signal per color channel
    chanlims = channel_clims(clim[])
    rsig = Observable(chanlims[1])
    gsig = Observable(chanlims[2])
    bsig = Observable(chanlims[3])
    #make sure that changes to individual channels update the color clim signal and vice versa
    Observables.ObservablePair(clim, rsig; f=x->channel_clim(red, x),   g=x->change_red(clim, x))
    Observables.ObservablePair(clim, gsig; f=x->channel_clim(green, x), g=x->change_green(clim, x))
    Observables.ObservablePair(clim, bsig; f=x->channel_clim(blue, x),  g=x->change_blue(clim, x))
    names = ["Red Contrast"; "Green Contrast"; "Blue Contrast"]
    csigs = [rsig; gsig; bsig]
    cguis = []
    for i=1:length(hists)
        push!(cguis, contrast_gui(enabled, hists[i], csigs[i]; wname = names[i]))
    end
    return cguis
end

contrast_gui(enabled, hist::Vector, clim) = contrast_gui(enabled, hist[1], clim)

function contrast_gui(enabled::Observable{Bool}, hist::Observable, clim::Observable; wname="Contrast")
    vhist, vclim = hist[], clim[]
    T = eltype(vclim)
    Δ = T <: Integer ? T(1) : eps(T)
    rng = vhist.edges[1]
    cmin, cmax = vclim.min, vclim.max
    if !(cmin < cmax)
        cmin, cmax = first(rng), last(rng)
        if !(cmin < cmax)
            cmin, cmax = zero(cmin), oneunit(cmax)
        end
    end
    smin = Observable(convert(eltype(rng), cmin))
    smax = Observable(convert(eltype(rng), cmax))
    cgui = contrast_gui_layout(smin, smax, rng; wname=wname)
    signal_connect(cgui["window"], :destroy) do widget
        enabled[] = false
    end
    updateclim = map(smin, smax) do cmin, cmax
        # if min/max is outside the current range, update the sliders
        adj = Gtk4.adjustment(widget(cgui["slider_min"]))
        rmin, rmax = Gtk4.G_.get_lower(adj), Gtk4.G_.get_upper(adj)
        if cmin < rmin || cmax > rmax || cmax-cmin < Δ
            # Also, don't cross the sliders
            bigmax = max(cmin,cmax,rmin,rmax)
            bigmin = min(cmin,cmax,rmin,rmax)
            thismax = min(typemax(T), max(cmin, cmax, rmax))
            thismin = max(typemin(T), min(cmin, cmax, rmin))
            rng = range(thismin, stop=thismax, length=255)
            cminT, cmaxT = T(min(cmin, cmax)), T(max(cmin, cmax))
            if cminT == cmaxT
                cminT = min(cminT, cminT-Δ)
                cmaxT = max(cmaxT, cmaxT+Δ)
            end
            mn, mx = minimum(rng), maximum(rng)
            cmin, cmax = T(clamp(cminT, mn, mx)), T(clamp(cmaxT, mn, mx))
            if cmin != cgui["slider_min"][] || cmax != cgui["slider_max"][]
                cgui["slider_min"][] = (rng, float(cmin))
                cgui["slider_max"][] = (rng, float(cmax))
            end
        end
        # Update the image contrast
        clim[] = CLim(cmin, cmax)
    end
    # TODO: we might want to throttle this?
    redraw = draw(cgui["canvas"], hist) do cnvs, hst
        if isvisible(cgui["window"]) # protects against window destruction
            rng, cl = hst.edges[1], clim[]
            mn, mx = minimum(rng), maximum(rng)
            cgui["slider_min"][] = (rng, clamp(cl.min, mn, mx))
            cgui["slider_max"][] = (rng, clamp(cl.max, mn, mx))
            drawhist(cnvs, hst)
        end
    end
    GtkObservables.gc_preserve(cgui["window"], (cgui, redraw, updateclim))
    cgui
end

function contrast_gui_layout(smin::Observable, smax::Observable, rng; wname="Contrast")
    win = GtkWindow(wname)
    g = GtkGrid()
    win[] = g
    window_wrefs[win] = nothing
    signal_connect(win, :destroy) do w
        delete!(window_wrefs, win)
    end
    slmax = slider(rng; observable=smax)
    slmin = slider(rng; observable=smin)
    for sl in (slmax, slmin)
        Gtk4.draw_value(widget(sl), false)
    end
    g[1,1] = widget(slmax)
    cnvs = canvas(UserUnit)
    g[1,2] = widget(cnvs)
    g[1,3] = widget(slmin)
    widget(cnvs).hexpand = widget(cnvs).vexpand = true
    Gtk4.content_height(widget(cnvs), 100)
    emax_w = GtkEntry(; width_chars=5, hexpand=false)
    emin_w = GtkEntry(; width_chars=5, hexpand=false)
    g[2,1] = emax_w
    g[2,3] = emin_w
    # By not specifying the range on the textbox, we let the user
    # enter something out-of-range, which can be handy in some
    # circumstances.
    emax = textbox(eltype(smax); widget=emax_w, observable=smax) # , range=rng)
    emin = textbox(eltype(smin); widget=emin_w, observable=smin) #, range=rng)

    Dict("window"=>win, "canvas"=>cnvs, "slider_min"=>slmin, "slider_max"=>slmax, "textbox_min"=>emin, "textbox_max"=>emax)
end

# We could use one of the plotting toolkits, but most are pretty slow
# to load and/or produce the first plot. So let's just do it manually.
@guarded function drawhist(canvas, hist)
    ctx = getgc(canvas)
    fill!(canvas, colorant"white")
    edges, counts = hist.edges[1], hist.weights
    xmin, xmax = first(edges), last(edges)
    cmax = maximum(counts)
    if cmax <= 0 || !(xmin < xmax)
        return nothing
    end
    set_coordinates(ctx, BoundingBox(xmin, xmax, log10(cmax+1), 0))
    set_source(ctx, colorant"black")
    move_to(ctx, xmax, 0)
    line_to(ctx, xmin, 0)
    for (i, c) in enumerate(counts)
        line_to(ctx, edges[i], log10(c+1))
        line_to(ctx, edges[i+1], log10(c+1))
    end
    line_to(ctx, xmax, 0)
    fill(ctx)
    nothing
end
