# Confidence Levels

El campo `confidence` (0.0–1.0) en suggestions y action items indica la certeza del agente sobre la detección o propuesta.

## Convención recomendada

| Level | Score | When to use |
|-------|-------|-------------|
| `CERTAIN` | 1.0 | Verificado manualmente o por evidencia matemática (ej: hash mismatch detectado) |
| `VERY_HIGH` | 0.95 | Detectado por múltiples fuentes independientes (ej: el mismo CVE reportado por Snyk + Trivy + GitHub) |
| `HIGH` | 0.85 | Análisis de alta certeza, una sola fuente confiable |
| `MEDIUM` | 0.70 | Requiere verificación humana antes de actuar (ej: refactoring sugerido por static analysis) |
| `LOW` | 0.50 | Posible false positive — investigar primero |
| `UNCERTAIN` | 0.30 | Investigación necesaria antes de cualquier acción |

## Cómo afecta el comportamiento

El sistema **no** aplica políticas automáticas basadas en confidence — es informativo para que humanos y otros agentes puedan filtrar/priorizar.

Patrones recomendados:
- **Auto-approval gate**: si tu organización tiene un agente "aprobador automático", podría auto-aprobar suggestions con `confidence >= 0.95`.
- **Filter en dashboard**: la UI puede ocultar por default suggestions con `confidence < 0.70`.
- **Retry policy del executor**: failed con `confidence > 0.90` reintenta hasta 3 veces; failed con `confidence < 0.70` no reintenta.

## En el código del agente

```javascript
const confidenceLevels = {
  CERTAIN: 1.0,
  VERY_HIGH: 0.95,
  HIGH: 0.85,
  MEDIUM: 0.70,
  LOW: 0.50,
  UNCERTAIN: 0.30
};

await api.post(`/governance/action_item/${aiId}/suggestions`, {
  created_by: 'agent:vuln-scanner',
  owner: 'executor:pr-creator',
  confidence: confidenceLevels.VERY_HIGH,
  // ...
});
```

## Anti-patterns

- **No usar confidence como estimador de impacto** — el impacto va en `value` + `priority`.
- **No mezclar escalas** — siempre 0.0–1.0, no 0–100.
- **No omitir confidence en suggestions ejecutables** — el executor necesita decidir retry policy.
