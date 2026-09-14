import { useCallback, useEffect, useRef, useState } from 'react';
import { useMapRootState } from '@/hooks/Mapper/mapRootProvider';
import { RoutesType } from '@/hooks/Mapper/mapRootProvider/types.ts';
import { LoadRoutesCommand } from '@/hooks/Mapper/components/mapInterface/widgets/RoutesWidget/types.ts';
import { RoutesList } from '@/hooks/Mapper/types/routes.ts';

function usePrevious<T>(value: T): T | undefined {
  const ref = useRef<T>();

  useEffect(() => {
    ref.current = value;
  }, [value]);

  return ref.current;
}

type UseLoadRoutesProps = {
  loadRoutesCommand: LoadRoutesCommand;
  hubs: string[];
  routesList: RoutesList | undefined;
  data: RoutesType;
  deps?: unknown[];
};

export const useLoadRoutes = ({
  data: routesSettings,
  loadRoutesCommand,
  hubs,
  routesList,
  deps = [],
}: UseLoadRoutesProps) => {
  const [loading, setLoading] = useState(false);

  const {
    data: { selectedSystems, systems, connections },
  } = useMapRootState();

  const prevSys = usePrevious(systems);
  const ref = useRef({ prevSys, selectedSystems, routesSettings });
  ref.current = { prevSys, selectedSystems, routesSettings };

  // Reload when any setting changes. The serialized form is compared as one
  // value, so two toggles applied together (one on, one off) still trigger a
  // reload - a sorted list of the values would not change in that case.
  const routesSettingsKey = JSON.stringify(routesSettings);

  const loadRoutes = useCallback(
    (systemId: string, routesSettings: RoutesType) => {
      loadRoutesCommand(systemId, routesSettings);
      setLoading(true);
    },
    [loadRoutesCommand],
  );

  useEffect(() => {
    setLoading(false);
  }, [routesList]);

  useEffect(() => {
    if (selectedSystems.length !== 1) {
      return;
    }

    const [systemId] = selectedSystems;
    loadRoutes(systemId, ref.current.routesSettings);
  }, [loadRoutes, selectedSystems, systems?.length, connections, hubs, routesSettingsKey, ...deps]);

  return { loading, loadRoutes, setLoading };
};
