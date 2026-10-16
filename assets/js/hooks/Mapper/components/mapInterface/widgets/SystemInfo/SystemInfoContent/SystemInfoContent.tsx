import { useMapRootState } from '@/hooks/Mapper/mapRootProvider';
import { isWormholeSpace } from '@/hooks/Mapper/components/map/helpers/isWormholeSpace.ts';
import { useMemo } from 'react';
import { getSystemById, sortWHClasses } from '@/hooks/Mapper/helpers';
import { InfoDrawer, MarkdownTextViewer, WHClassView, WHEffectView } from '@/hooks/Mapper/components/ui-kit';
import { getSystemStaticInfo } from '@/hooks/Mapper/mapRootProvider/hooks/useLoadSystemStatic';
import { LabelsManager } from '@/hooks/Mapper/utils/labelsManager.ts';

interface SystemInfoContentProps {
  systemId: string;
  onEditClick?(): void;
}
export const SystemInfoContent = ({ systemId }: SystemInfoContentProps) => {
  const {
    data: { systems, wormholesData },
  } = useMapRootState();

  const sys = getSystemById(systems, systemId)! || {};
  const systemStaticInfo = getSystemStaticInfo(systemId)!;
  const { description, labels } = sys;
  const temporaryNotes = useMemo(() => new LabelsManager(labels ?? '').temporaryNotes, [labels]);
  const { system_class, region_name, constellation_name, statics, effect_name, effect_power } = systemStaticInfo || {};
  const isWH = isWormholeSpace(system_class);
  const sortedStatics = useMemo(() => sortWHClasses(wormholesData, statics), [wormholesData, statics]);

  return (
    <div className="flex flex-col gap-1 p-2">
      <InfoDrawer title="Constellation & Region">
        {constellation_name} / {region_name}
      </InfoDrawer>

      {isWH && (
        <InfoDrawer title="Statics">
          <div className="flex gap-1">
            {sortedStatics.map(x => (
              <WHClassView key={x} whClassName={x} />
            ))}
          </div>
        </InfoDrawer>
      )}

      {isWH && effect_name && (
        <InfoDrawer title="Effect">
          <WHEffectView effectName={effect_name} effectPower={effect_power} />
        </InfoDrawer>
      )}

      {description && (
        <InfoDrawer
          title={
            <div className="flex gap-1 items-center">
              <div>Description</div>
            </div>
          }
        >
          <MarkdownTextViewer>{description}</MarkdownTextViewer>
        </InfoDrawer>
      )}

      {temporaryNotes && (
        <InfoDrawer
          title={
            <div className="flex gap-1 items-center">
              <div>Temporary Notes</div>
            </div>
          }
        >
          <MarkdownTextViewer>{temporaryNotes}</MarkdownTextViewer>
        </InfoDrawer>
      )}
    </div>
  );
};
