import { Widget } from '@/hooks/Mapper/components/mapInterface/components';
import { useMapRootState } from '@/hooks/Mapper/mapRootProvider';
import {
  LayoutEventBlocker,
  LoadingWrapper,
  SystemView,
  TooltipPosition,
  WdCheckbox,
  WdImgButton,
} from '@/hooks/Mapper/components/ui-kit';
import { useLoadSystemStatic } from '@/hooks/Mapper/mapRootProvider/hooks/useLoadSystemStatic.ts';

import { forwardRef, Fragment, MouseEvent, ReactNode, useCallback, useEffect, useMemo, useRef, useState } from 'react';
import classes from './RoutesWidget.module.scss';
import { RoutesList } from './RoutesList';
import clsx from 'clsx';
import { Route } from '@/hooks/Mapper/types/routes.ts';
import { SolarSystemStaticInfoRaw } from '@/hooks/Mapper/types/system.ts';
import { OutCommand } from '@/hooks/Mapper/types/mapHandlers.ts';
import { PrimeIcons } from 'primereact/api';
import { RoutesSettingsDialog } from './RoutesSettingsDialog';
import { RoutesProvider, useRouteProvider } from './RoutesProvider.tsx';
import { ContextMenuSystemInfo, useContextMenuSystemInfoHandlers } from '@/hooks/Mapper/components/contexts';
import useMaxWidth from '@/hooks/Mapper/hooks/useMaxWidth.ts';
import { WdTooltipWrapper } from '@/hooks/Mapper/components/ui-kit/WdTooltipWrapper';
import {
  AddSystemDialog,
  SearchOnSubmitCallback,
} from '@/hooks/Mapper/components/mapInterface/components/AddSystemDialog';
import {
  RoutesImperativeHandle,
  RoutesWidgetProps,
} from '@/hooks/Mapper/components/mapInterface/widgets/RoutesWidget/types.ts';

const sortByDist = (a: Route, b: Route) => {
  const distA = a.has_connection ? a.systems?.length || 0 : Infinity;
  const distB = b.has_connection ? b.systems?.length || 0 : Infinity;

  return distA - distB;
};

export const RoutesWidgetContent = () => {
  const {
    outCommand,
    data: { selectedSystems, systems, isSubscriptionActive },
  } = useMapRootState();
  const { hubs = [], routesList, isRestricted, loading, nohubsPlaceholder, data: routesSettings } = useRouteProvider();

  const [systemId] = selectedSystems;

  const { systems: systemStatics, loadSystems } = useLoadSystemStatic({ systems: hubs ?? [] });
  const { open, ...systemCtxProps } = useContextMenuSystemInfoHandlers();

  // Alternative routes fetched lazily per destination when a row is expanded.
  const [expanded, setExpanded] = useState<Set<string>>(new Set());
  const [alternatives, setAlternatives] = useState<Record<string, 'loading' | Route[]>>({});
  const [altStatics, setAltStatics] = useState<SolarSystemStaticInfoRaw[]>([]);

  const staticsById = useMemo(() => {
    const byId = new Map<number, SolarSystemStaticInfoRaw>();
    [...(routesList?.systems_static_data ?? []), ...altStatics].forEach(s => s && byId.set(s.solar_system_id, s));
    return byId;
  }, [routesList?.systems_static_data, altStatics]);

  const preparedRoutes: Route[] = useMemo(() => {
    return (
      routesList?.routes
        .sort(sortByDist)
        // .filter(x => x.destination.toString() !== systemId)
        .map(route => ({
          ...route,
          mapped_systems: route.systems?.map(solar_system_id => staticsById.get(solar_system_id)) ?? [],
        })) ?? []
    );
  }, [routesList?.routes, staticsById, systemId]);

  const refData = useRef({ open, loadSystems, preparedRoutes, expanded, alternatives, outCommand, routesSettings, systemId });
  refData.current = { open, loadSystems, preparedRoutes, expanded, alternatives, outCommand, routesSettings, systemId };

  useEffect(() => {
    (async () => await refData.current.loadSystems(hubs))();
  }, [hubs]);

  // Alternatives are only valid for the origin/settings they were computed
  // with - drop them when either changes.
  useEffect(() => {
    setExpanded(new Set());
    setAlternatives({});
    setAltStatics([]);
  }, [systemId, routesSettings]);

  const handleToggleAlternatives = useCallback(async (destination: string) => {
    const current = refData.current;
    const next = new Set(current.expanded);

    if (next.has(destination)) {
      next.delete(destination);
      setExpanded(next);
      return;
    }

    next.add(destination);
    setExpanded(next);

    if (current.alternatives[destination] != null) {
      return;
    }

    setAlternatives(prev => ({ ...prev, [destination]: 'loading' }));

    try {
      const resp = (await current.outCommand({
        type: OutCommand.getRouteAlternatives,
        data: {
          system_id: current.systemId,
          destination_id: destination,
          routes_settings: current.routesSettings,
        },
      })) as { routes?: Route[]; systems_static_data?: SolarSystemStaticInfoRaw[] };

      setAlternatives(prev => ({ ...prev, [destination]: resp?.routes ?? [] }));

      if (resp?.systems_static_data?.length) {
        setAltStatics(prev => [...prev, ...(resp.systems_static_data ?? []).filter(Boolean)]);
      }
    } catch (err) {
      console.warn('Failed to load route alternatives', err);
      setAlternatives(prev => ({ ...prev, [destination]: [] }));
    }
  }, []);

  const handleClick = useCallback((e: MouseEvent, systemId: string) => {
    const route = refData.current.preparedRoutes.find(x => x.destination.toString() === systemId);

    refData.current.open(e, systemId, route?.mapped_systems ?? []);
  }, []);

  const handleContextMenu = useCallback(
    async (e: MouseEvent, systemId: string) => {
      await refData.current.loadSystems([systemId]);
      handleClick(e, systemId);
    },
    [handleClick],
  );

  if (isRestricted && !isSubscriptionActive) {
    return (
      <div className="w-full h-full flex items-center justify-center">
        <span className="select-none text-center text-stone-400/80 text-sm">
          User Routes available with &#39;Active&#39; map subscription only (contact map administrators)
        </span>
      </div>
    );
  }

  if (!systemId) {
    return (
      <div className="w-full h-full flex justify-center items-center select-none text-center text-stone-400/80 text-sm">
        System is not selected
      </div>
    );
  }

  if (hubs.length === 0) {
    return (
      <div className="w-full h-full flex justify-center items-center select-none">
        {nohubsPlaceholder ?? 'Routes not set'}
      </div>
    );
  }

  return (
    <>
      <LoadingWrapper loading={loading}>
        <div className={clsx(classes.RoutesGrid, 'px-2 py-2')}>
          {preparedRoutes.map(route => {
            const destKey = route.destination.toString();
            const isExpanded = expanded.has(destKey);
            const altState = alternatives[destKey];

            // The reply's first route is rank #1 (usually the shown one);
            // only the ranks after it are alternatives.
            const altRoutes =
              Array.isArray(altState) && altState.length > 1
                ? altState.slice(1).map(alt => ({
                    ...alt,
                    mapped_systems: alt.systems?.map(solar_system_id => staticsById.get(solar_system_id)) ?? [],
                  }))
                : [];

            return (
              <Fragment key={destKey}>
                <div className="flex gap-2 items-center">
                  <WdImgButton
                    className={clsx(PrimeIcons.BARS, classes.RemoveBtn)}
                    onClick={e => handleClick(e, destKey)}
                    tooltip={{
                      content: 'Click here to open system menu',
                      position: TooltipPosition.top,
                      offset: 10,
                    }}
                  />
                  {route.has_connection && (
                    <WdImgButton
                      className={clsx(isExpanded ? PrimeIcons.ANGLE_DOWN : PrimeIcons.ANGLE_RIGHT, classes.RemoveBtn)}
                      onClick={() => handleToggleAlternatives(destKey)}
                      tooltip={{
                        content: 'Show alternative routes',
                        position: TooltipPosition.top,
                        offset: 10,
                      }}
                    />
                  )}
                  <SystemView
                    systemId={destKey}
                    className={clsx('select-none text-center cursor-context-menu')}
                    hideRegion
                    compact
                    showCustomName
                  />
                </div>
                <div
                  className={clsx('text-right pl-1', route.has_connection && 'cursor-pointer')}
                  onClick={route.has_connection ? () => handleToggleAlternatives(destKey) : undefined}
                >
                  {route.has_connection ? (route.systems?.length ?? 2) : ''}
                </div>
                <div className="pl-2 pb-0.5">
                  <RoutesList data={route} onContextMenu={handleContextMenu} />
                </div>

                {isExpanded && altState === 'loading' && (
                  <>
                    <div />
                    <div />
                    <div className="pl-2 pb-0.5 text-stone-400">
                      <i className="pi pi-spin pi-spinner mr-1 text-[10px]" />
                      Loading alternatives...
                    </div>
                  </>
                )}

                {isExpanded && Array.isArray(altState) && altRoutes.length === 0 && (
                  <>
                    <div />
                    <div />
                    <div className="pl-2 pb-0.5 text-stone-400 select-none">No alternative routes</div>
                  </>
                )}

                {isExpanded &&
                  altRoutes.map((alt, idx) => (
                    <Fragment key={`${destKey}-alt-${idx}`}>
                      <div className="text-right text-stone-400 select-none pr-1">#{idx + 2}</div>
                      <div className="text-right pl-1 text-stone-400">{alt.systems?.length ?? ''}</div>
                      <div className="pl-2 pb-0.5">
                        <RoutesList data={alt} onContextMenu={handleContextMenu} />
                      </div>
                    </Fragment>
                  ))}
              </Fragment>
            );
          })}
        </div>
      </LoadingWrapper>
      <ContextMenuSystemInfo
        routes={preparedRoutes}
        systems={systems}
        systemStatics={systemStatics}
        systemIdFrom={systemId}
        {...systemCtxProps}
      />
    </>
  );
};

type RoutesWidgetCompProps = {
  title: ReactNode | string;
  renderContent?: (content: ReactNode, compact: boolean) => ReactNode;
};

export const RoutesWidgetComp = ({ title, renderContent }: RoutesWidgetCompProps) => {
  const [routeSettingsVisible, setRouteSettingsVisible] = useState(false);
  const { data, update, addHubCommand } = useRouteProvider();

  const isSecure = data.path_type === 'secure';
  const handleSecureChange = useCallback(() => {
    update({
      ...data,
      path_type: data.path_type === 'secure' ? 'shortest' : 'secure',
    });
  }, [data, update]);

  const ref = useRef<HTMLDivElement>(null);
  const compact = useMaxWidth(ref, 170);
  const [openAddSystem, setOpenAddSystem] = useState<boolean>(false);

  const onAddSystem = useCallback(() => setOpenAddSystem(true), []);

  const handleSubmitAddSystem: SearchOnSubmitCallback = useCallback(
    async item => addHubCommand?.(item.value.toString()),
    [addHubCommand],
  );

  return (
    <Widget
      label={
        <div className="flex justify-between items-center text-xs w-full" ref={ref}>
          <div className="select-none flex items-center gap-2">{title}</div>
          <LayoutEventBlocker className="flex items-center gap-2">
            {addHubCommand && (
              <WdImgButton
                className={PrimeIcons.PLUS_CIRCLE}
                onClick={onAddSystem}
                tooltip={{
                  content: 'Click here to add new system to routes',
                }}
              />
            )}

            <WdTooltipWrapper content="Prefer high-sec routes" position={TooltipPosition.top}>
              <WdCheckbox
                size="xs"
                labelSide="left"
                label={compact ? '' : 'Prefer safest'}
                value={isSecure}
                onChange={handleSecureChange}
                classNameLabel="whitespace-nowrap"
              />
            </WdTooltipWrapper>
            <WdImgButton
              className={PrimeIcons.SLIDERS_H}
              onClick={() => setRouteSettingsVisible(true)}
              tooltip={{
                position: TooltipPosition.top,
                content: 'Click here to open Routes settings',
              }}
            />
          </LayoutEventBlocker>
        </div>
      }
    >
      {renderContent ? (
        renderContent(
          <div className="h-full overflow-auto bg-opacity-5 custom-scrollbar">
            <RoutesWidgetContent />
          </div>,
          compact,
        )
      ) : (
        <div className="h-full overflow-auto bg-opacity-5 custom-scrollbar">
          <RoutesWidgetContent />
        </div>
      )}

      <RoutesSettingsDialog visible={routeSettingsVisible} setVisible={setRouteSettingsVisible} />

      {addHubCommand && (
        <AddSystemDialog
          title="Add system to routes"
          visible={openAddSystem}
          setVisible={() => setOpenAddSystem(false)}
          onSubmit={handleSubmitAddSystem}
        />
      )}
    </Widget>
  );
};

export const RoutesWidget = forwardRef<RoutesImperativeHandle, RoutesWidgetProps & RoutesWidgetCompProps>(
  ({ title, renderContent, ...props }, ref) => {
    return (
      <RoutesProvider {...props} ref={ref}>
        <RoutesWidgetComp title={title} renderContent={renderContent} />
      </RoutesProvider>
    );
  },
);
RoutesWidget.displayName = 'RoutesWidget';
