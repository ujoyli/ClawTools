---
title: "Software Architecture As Code Tools"
subtitle: "An overview of architecture/diagrams as code tools"
author: "Dr Milan Milanović"
url: https://newsletter.techworld-with-milan.com/p/software-architecture-as-code-tools
---

# Software Architecture As Code Tools

*An overview of architecture/diagrams as code tools*

We’re seeing more and more tools that enable you to create software architecture and other diagrams as code. The main benefit of using this concept is that the majority of the diagrams as code tools can be scripted and integrated into a built pipeline for generating automatic documentation.

The other benefit responsible for the growing use of diagrams as code to create software architecture is that it enables text-based tooling, which most software developers already use.

What are some existing tools for creating such diagrams?

1. **[Structurizr](https://structurizr.com/)**

Create multiple diagrams from a single **(C4) model**. It allows the creating of numerous diagrams from a single model using different tools and programming languages.

[![](images/888cf099-dd0c-43b2-8d29-81d8abe97520_1172x588.png)](https://substackcdn.com/image/fetch/$s_!HGaa!,f_auto,q_auto:good,fl_progressive:steep/https%3A%2F%2Fsubstack-post-media.s3.amazonaws.com%2Fpublic%2Fimages%2F888cf099-dd0c-43b2-8d29-81d8abe97520_1172x588.png)Structurizr

For C4 models, you can also use tools such as **[C4Sharp](https://github.com/8T4/c4sharp)**, a .net library for building diagrams as code.

1. **[PlantUML](https://plantuml.com/)**

It is an open-source tool that allows users to create diagrams from a plain text language. With PlantUML, you can make different kinds of UML and non-UML diagrams, too (Sequence, Class, Component, JSON data, Network, Gantt, etc.).

[![](images/b8c9d6b0-6f3f-4261-96f7-5079253df281_675x495.png)](https://substackcdn.com/image/fetch/$s_!TBbd!,f_auto,q_auto:good,fl_progressive:steep/https%3A%2F%2Fsubstack-post-media.s3.amazonaws.com%2Fpublic%2Fimages%2Fb8c9d6b0-6f3f-4261-96f7-5079253df281_675x495.png)PlantUML

1. **[Diagrams](https://github.com/mingrammer/diagrams)**

Turn Python code into cloud system architecture diagrams. A new or current system design can also be explained or represented visually. The primary significant providers that Diagrams presently supports include **AWS, Azure, GCP, Kubernetes, Alibaba Cloud, Oracle Cloud**, etc.

[![](images/235b2242-dfda-428c-874e-2d61aeafa03b_904x617.png)](https://substackcdn.com/image/fetch/$s_!CJ85!,f_auto,q_auto:good,fl_progressive:steep/https%3A%2F%2Fsubstack-post-media.s3.amazonaws.com%2Fpublic%2Fimages%2F235b2242-dfda-428c-874e-2d61aeafa03b_904x617.png)Diagrams

4. **[Mermaid](https://github.com/mermaid-js/mermaid)**

Mermaid is a **JavaScript-based diagramming and charting tool** that uses Markdown-inspired text definitions and a renderer to create and modify complex diagrams. The primary purpose of Mermaid is to help documentation catch up with development.

[![](images/bc7c28fd-701d-4f43-b53e-29e3d7c3a094_843x830.png)](https://substackcdn.com/image/fetch/$s_!h9_e!,f_auto,q_auto:good,fl_progressive:steep/https%3A%2F%2Fsubstack-post-media.s3.amazonaws.com%2Fpublic%2Fimages%2Fbc7c28fd-701d-4f43-b53e-29e3d7c3a094_843x830.png)Mermaid

1. **[ASCII editor](https://asciiflow.com/)**

ASCII Flow is a simple and easy-to-use online flowchart software that uses ASCII characters to create flowcharts. It allows users to create flowcharts by simply typing the diagram using ASCII characters and then converting it into a visual flowchart. It can create flowcharts, diagrams, and other types of visual diagrams.

[![](images/beabfa71-811b-4579-83ed-7544fe1d05ce_647x383.png)](https://substackcdn.com/image/fetch/$s_!bx55!,f_auto,q_auto:good,fl_progressive:steep/https%3A%2F%2Fsubstack-post-media.s3.amazonaws.com%2Fpublic%2Fimages%2Fbeabfa71-811b-4579-83ed-7544fe1d05ce_647x383.png)ASCIIFlow

1. **[Markmap](https://markmap.js.org/)**

Markmap is a tool that allows you to create and edit mind maps. Markmap uses a technology called Markdown, which is a lightweight markup language, to create and edit mind maps.

[![](images/ed07b322-07ce-49fb-94a3-b14971994cf0_1487x675.png)](https://substackcdn.com/image/fetch/$s_!DZUl!,f_auto,q_auto:good,fl_progressive:steep/https%3A%2F%2Fsubstack-post-media.s3.amazonaws.com%2Fpublic%2Fimages%2Fed07b322-07ce-49fb-94a3-b14971994cf0_1487x675.png)Markmap

1. **[Go diagrams](https://github.com/blushft/go-diagrams)**

It is a similar tool to Diagrams but with Go as a diagramming language.

[![](images/42b17a42-6fd9-4d3d-b19a-393edb2315ce_638x969.png)](https://substackcdn.com/image/fetch/$s_!qNNi!,f_auto,q_auto:good,fl_progressive:steep/https%3A%2F%2Fsubstack-post-media.s3.amazonaws.com%2Fpublic%2Fimages%2F42b17a42-6fd9-4d3d-b19a-393edb2315ce_638x969.png)Go diagrams

1. **[SequenceDiagram.org](https://sequencediagram.org/)**

Sequencediagram.org is a tool that provides a simple online tool for creating and sharing UML sequence diagrams.

[![](images/5fcf6591-dd84-4dc0-af03-ffa310e9c4c9_1205x415.png)](https://substackcdn.com/image/fetch/$s_!Ud6U!,f_auto,q_auto:good,fl_progressive:steep/https%3A%2F%2Fsubstack-post-media.s3.amazonaws.com%2Fpublic%2Fimages%2F5fcf6591-dd84-4dc0-af03-ffa310e9c4c9_1205x415.png)SequenceDiagram.org

Along with these diagrams as code tools, there are other **software architecture tools**, such as:

**Modeling tools:**

- [IcePanel](https://icepanel.io/)
- [Enterprise Architect](https://sparxsystems.com/)
- [Archi](https://www.archimatetool.com/)
- [Carbide](https://carbide.dev/)
- [StarUML](https://staruml.io/)

**Diagramming tools:**

- [Visio](https://www.microsoft.com/en-ca/microsoft-365/visio/flowchart-software)
- [LucidChart](https://www.lucidchart.com/pages/solutions/engineering)
- [Draw.io](http://draw.io/)
- [Cloudcraft](https://www.cloudcraft.co/)
- [Archium](https://archium.io/)
- [Excalidraw](https://excalidraw.com/)
- [CloudSkew](https://www.cloudskew.com/)

Check the complete list of tools here: [https://softwarearchitecture.tools/](https://softwarearchitecture.tools/).

[![](images/84ce768b-3341-4282-b474-d5f08f11030b_1059x644.png)](https://substackcdn.com/image/fetch/$s_!fteW!,f_auto,q_auto:good,fl_progressive:steep/https%3A%2F%2Fsubstack-post-media.s3.amazonaws.com%2Fpublic%2Fimages%2F84ce768b-3341-4282-b474-d5f08f11030b_1059x644.png)Software architecture tools

---

Thanks for reading Tech World With Milan Newsletter! Subscribe for free to receive new posts and support my work.