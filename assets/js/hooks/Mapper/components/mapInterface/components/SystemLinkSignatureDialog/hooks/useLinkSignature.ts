import { useCallback, useEffect, useRef, useState } from 'react';

import { copyToClipboard, formatBookmarkName } from '@/hooks/Mapper/helpers/bookmarkFormatHelper.ts';
import { parseSignatureCustomInfo } from '@/hooks/Mapper/helpers/parseSignatureCustomInfo';
import { useMapRootState } from '@/hooks/Mapper/mapRootProvider';
import { CommandLinkSignatureToSystem, SystemSignature } from '@/hooks/Mapper/types';
import { OutCommand } from '@/hooks/Mapper/types/mapHandlers.ts';

export interface UseLinkSignatureProps {
  data: CommandLinkSignatureToSystem;
  targetSystemClassGroup: string | null;
}

export const useLinkSignature = ({ data, targetSystemClassGroup }: UseLinkSignatureProps) => {
  const {
    outCommand,
    data: { systemSignatures, systems, wormholesData },
  } = useMapRootState();

  const ref = useRef({ outCommand });
  ref.current = { outCommand };

  const [userSettings, setUserSettings] = useState<any>(null);

  useEffect(() => {
    outCommand({ type: OutCommand.getUserSettings, data: null })
      .then((res: any) => setUserSettings(res?.user_settings))
      .catch((e: any) => console.warn('Failed to fetch user settings', e));
  }, [outCommand]);

  const handleLinkSignature = useCallback(
    async (signature: SystemSignature) => {
      const { outCommand } = ref.current;

      // Linking triggers server-side auto-labeling (chain indexes, system
      // tags/labels and temporary names are map-level options applied for
      // every user); the reply carries the signature with its assigned chain
      // data so the bookmark name can be formatted from authoritative values.
      const response = (await outCommand({
        type: OutCommand.linkSignatureToSystem,
        data: {
          ...data,
          signature_eve_id: signature.eve_id,
        },
      })) as { signature?: SystemSignature | null };

      const linkedSignature = response?.signature;

      if (userSettings?.bookmark_name_format && userSettings?.bookmark_auto_copy !== false && linkedSignature) {
        const sourceSystem = systems.find(
          (s: any) => s.system_static_info?.solar_system_id === data.solar_system_source,
        );
        const systemUuid = sourceSystem?.id || data.solar_system_source.toString();
        const info = parseSignatureCustomInfo(linkedSignature.custom_info);

        const formattedStr = formatBookmarkName(
          userSettings.bookmark_name_format,
          linkedSignature,
          targetSystemClassGroup,
          info.bookmark_index ?? '',
          wormholesData,
          userSettings.bookmark_wormholes_start_at_zero,
          userSettings.bookmark_custom_mapping,
          systemSignatures,
          systemUuid,
          data.solar_system_source.toString(),
        );

        await copyToClipboard(formattedStr);
      }
    },
    [data, userSettings, targetSystemClassGroup, systemSignatures, systems, wormholesData],
  );

  return { handleLinkSignature };
};
