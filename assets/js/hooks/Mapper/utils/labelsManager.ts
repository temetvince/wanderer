export type LabelsType = {
  customLabel: string;
  labels: string[];
  // Fork: free text cleared by the server when the system leaves the map.
  tempNotes?: string;
};

export class LabelsManager {
  protected labelsRaw: string;
  protected parsedLabels: LabelsType = {
    labels: [],
    customLabel: '',
  };
  constructor(labels: string) {
    this.labelsRaw = labels;
    this.parsedLabels = this.parse();
  }

  parse(): LabelsType {
    try {
      return JSON.parse(this.labelsRaw) as LabelsType;
    } catch (err) {
      return {
        customLabel: '',
        labels: this.labelsRaw.split(','),
      };
    }
  }

  parse2(): LabelsType {
    if (this.labelsRaw.length === 0) {
      return {
        labels: [],
        customLabel: '',
      };
    }

    const [labels, customLabel] = this.labelsRaw.split(':');
    return {
      labels: labels.split(','),
      customLabel: customLabel ?? '',
    };
  }

  toString() {
    return JSON.stringify(this.parsedLabels);
  }

  toString2() {
    return `${this.parsedLabels.labels.join(',')}`;
  }

  valueOf() {
    return this.toString();
  }

  updateCustomLabel(label: string) {
    this.parsedLabels.customLabel = label;
  }

  addLabels(labels: string[]) {
    this.parsedLabels.labels = [...new Set([...this.parsedLabels.labels, ...labels])];
  }

  delLabels(labels: string[]) {
    this.parsedLabels.labels = this.parsedLabels.labels.filter(x => !labels.includes(x));
  }

  hasLabel(label: string) {
    return this.parsedLabels.labels?.includes(label);
  }

  toggleLabel(label: string) {
    if (this.parsedLabels.labels.includes(label)) {
      this.delLabels([label]);
    } else {
      this.addLabels([label]);
    }
  }

  clearLabels() {
    this.parsedLabels.labels = [];
  }

  get customLabel() {
    return this.parsedLabels.customLabel;
  }

  get temporaryNotes() {
    return this.parsedLabels.tempNotes ?? '';
  }

  updateTemporaryNotes(value: string) {
    const trimmed = value.trim();
    if (trimmed === '') {
      delete this.parsedLabels.tempNotes;
    } else {
      this.parsedLabels.tempNotes = value;
    }
  }

  get list() {
    return this.parsedLabels.labels;
  }
}
